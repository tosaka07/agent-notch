import AgentNotchCore
import Foundation

/// Selects the herdr pane a session runs in, and names the terminal that renders it.
///
/// herdr is a multiplexer with the same split as tmux — a background server owns the panes, a client
/// draws them inside an ordinary terminal — so activating the terminal alone lands on whichever pane
/// was focused last. Worse, the pane's processes hang off the *server*, which outlives its client and
/// is reparented to `launchd` on the first detach. From that moment no ancestor walk starting at the
/// session reaches a GUI application at all, and the session loses its terminal destination
/// entirely. Both halves are answered here: the pane is focused through herdr's socket, and the
/// application is looked for above the herdr *client* instead.
///
/// The pane comes from `HERDR_PANE_ID`, which herdr injects into every pane's PTY environment and
/// which the session's own process therefore inherits — the same handle `CmuxPaneJumper` reads for
/// cmux. `HERDR_SOCKET_PATH` arrives the same way, so a named session's socket needs no guessing.
enum HerdrPaneJumper {
    /// Everything needed to talk to one pane: which pane, and on which server.
    struct Location: Equatable {
        let paneId: String
        let socketPath: String
    }

    nonisolated static let paneEnvironmentKey = "HERDR_PANE_ID"
    nonisolated static let socketEnvironmentKey = "HERDR_SOCKET_PATH"
    nonisolated static let sessionEnvironmentKey = "HERDR_SESSION"

    typealias EnvironmentReader = (Int32) -> [String: String]?
    typealias ParentResolver = (Int32) -> Int32
    typealias Call = (
        _ method: String,
        _ params: [String: String],
        _ socketPath: String
    ) -> HerdrSocketClient.Response?

    // MARK: - Locating the pane

    /// Walks up from `pid` until a process carries herdr's pane environment.
    ///
    /// The session's own process almost always has it, since herdr injects it into the pane's shell
    /// and every child inherits it. The walk covers the anchors that sit further out — a tmux client,
    /// or a process picked off the TTY. It terminates at the herdr server, which runs without the
    /// variable.
    static func location(
        forProcessTree pid: Int32,
        environmentOf readEnvironment: EnvironmentReader = {
            ProcessEnvironment.environment(ofPID: $0)
        },
        parentOf resolveParent: ParentResolver = { TerminalJumper.parentPIDOf($0) },
        maximumDepth: Int = 15
    ) -> Location? {
        var currentPID = pid
        for _ in 0..<maximumDepth {
            if let environment = readEnvironment(currentPID),
                let paneId = environment[paneEnvironmentKey],
                isPaneIdentifier(paneId)
            {
                return Location(
                    paneId: paneId,
                    socketPath: environment[socketEnvironmentKey].flatMap { $0.isEmpty ? nil : $0 }
                        ?? defaultSocketPath
                )
            }
            let parent = resolveParent(currentPID)
            if parent <= 1 { return nil }
            currentPID = parent
        }
        return nil
    }

    /// Whether `value` has the shape herdr issues, such as `w6:p2`.
    ///
    /// The identifier is placed in a JSON value, so nothing here is standing between a stray
    /// character and a rewritten request. It keeps an unrelated variable of the same name — or a
    /// leftover from a pane that no longer exists — from being sent as if it addressed something.
    static func isPaneIdentifier(_ value: String) -> Bool {
        let halves = value.split(separator: ":", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return false }
        return isIdentifier(halves[0], prefix: "w") && isIdentifier(halves[1], prefix: "p")
    }

    private static func isIdentifier(_ half: Substring, prefix: Character) -> Bool {
        guard half.first == prefix, half.count > 1 else { return false }
        return half.dropFirst().allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// The socket of the unnamed session, which is the one an ordinary `herdr` run attaches to.
    static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/herdr/herdr.sock")
            .path
    }

    // MARK: - Driving herdr

    /// Focuses the pane, which moves herdr's workspace, tab and pane selection in one request.
    ///
    /// Returns false when herdr refuses or cannot be reached, which leaves the caller with a plain
    /// app activation — the pane the user was last in, rather than no jump at all.
    @discardableResult
    static func focusPane(_ location: Location, call: Call = liveCall) -> Bool {
        // `pane.focus` takes any pane and ships in the 0.8.0 schema, but is absent from the published
        // method table; `agent.focus` is the documented route and accepts the pane id as its target,
        // so it stands in wherever `pane.focus` is not recognised.
        if case .result = call("pane.focus", ["pane_id": location.paneId], location.socketPath) {
            Log.terminal.info("herdr pane \(location.paneId) focused")
            return true
        }
        if case .result = call("agent.focus", ["target": location.paneId], location.socketPath) {
            Log.terminal.info("herdr pane \(location.paneId) focused as an agent target")
            return true
        }
        Log.terminal.info("herdr: pane \(location.paneId) refused focus")
        return false
    }

    /// Whether herdr still holds this pane.
    ///
    /// An inherited environment variable is history: the pane it names is gone once its server
    /// restarted without it, or the pane was closed while the process it belonged to lived on. Asking
    /// herdr keeps a stale value from being offered as a destination.
    static func paneExists(_ location: Location, call: Call = liveCall) -> Bool {
        if case .result = call("pane.get", ["pane_id": location.paneId], location.socketPath) {
            return true
        }
        return false
    }

    /// The call every caller gets unless a test hands one in. A function rather than a stored
    /// closure: a `static let` of function type is global mutable state as far as concurrency
    /// checking is concerned.
    static func liveCall(
        method: String,
        params: [String: String],
        socketPath: String
    ) -> HerdrSocketClient.Response? {
        HerdrSocketClient.call(method: method, params: params, socketPath: socketPath)
    }

    // MARK: - Finding the client that draws the pane

    /// The herdr clients attached to `socketPath`, most recently started first.
    ///
    /// herdr publishes no client inventory — its API reaches clients only to set a window title — so
    /// the processes are matched by hand: a `herdr` executable that is not the server, and not an
    /// `--remote` attachment to someone else's machine, running against the session this socket
    /// belongs to. Several clients can attach to one server; focus is server-wide state, so any of
    /// their windows shows the pane, and the newest is the one the user attached last.
    static func clientPIDs(
        forSocketPath socketPath: String,
        candidates: () -> [Int32] = { herdrProcessIDs() },
        argumentsOf readArguments: (Int32) -> String = { arguments(ofPID: $0) },
        environmentOf readEnvironment: EnvironmentReader = {
            ProcessEnvironment.environment(ofPID: $0)
        }
    ) -> [Int32] {
        let wanted = sessionName(forSocketPath: socketPath)
        return candidates()
            .filter { pid in
                let arguments = readArguments(pid)
                guard !isServer(arguments: arguments), !isRemote(arguments: arguments) else {
                    return false
                }
                let session = clientSessionName(
                    arguments: arguments,
                    environment: readEnvironment(pid)
                )
                return session == wanted
            }
            .sorted(by: >)
    }

    /// The session a socket path belongs to; nil for the unnamed one.
    ///
    /// Named sessions live at `~/.config/herdr/sessions/<name>/herdr.sock`, so the directory above
    /// the socket names the session.
    static func sessionName(forSocketPath socketPath: String) -> String? {
        let components = URL(fileURLWithPath: socketPath).pathComponents
        guard components.count >= 3, components[components.count - 3] == "sessions" else {
            return nil
        }
        return components[components.count - 2]
    }

    /// The session a client was started against, read the way herdr resolves it itself: the explicit
    /// flag first, then the subcommand, then the environment.
    static func clientSessionName(arguments: String, environment: [String: String]?) -> String? {
        let tokens = arguments.split(separator: " ").map(String.init)
        if let flag = tokens.firstIndex(of: "--session"), tokens.count > flag + 1 {
            return tokens[flag + 1]
        }
        if let subcommand = tokens.firstIndex(of: "session"), tokens.count > subcommand + 2,
            tokens[subcommand + 1] == "attach"
        {
            return tokens[subcommand + 2]
        }
        return environment?[sessionEnvironmentKey].flatMap { $0.isEmpty ? nil : $0 }
    }

    static func isServer(arguments: String) -> Bool {
        arguments.split(separator: " ").dropFirst().first == "server"
    }

    /// A `--remote` client draws panes from a server on another machine, which no local application
    /// activation belongs to.
    static func isRemote(arguments: String) -> Bool {
        arguments.split(separator: " ").contains("--remote")
    }

    private static func executableName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Process inventory

    /// Every process running the `herdr` executable.
    ///
    /// The whole table is printed and filtered here rather than asked for by name: `pgrep -x herdr`
    /// was measured missing a running herdr server on this platform, and a lookup that can miss a
    /// client would silently cost the jump its window. Draining `ps` as it writes is what makes a
    /// table this size safe to ask for — see `TerminalJumper.runProcess`.
    static func herdrProcessIDs() -> [Int32] {
        TerminalJumper.runProcess("/bin/ps", args: ["-Ao", "pid=,comm="])
            .split(separator: "\n")
            .compactMap { line in
                let fields = line.split(
                    separator: " ",
                    maxSplits: 1,
                    omittingEmptySubsequences: true
                )
                guard fields.count == 2, let pid = Int32(fields[0]),
                    executableName(fields[1].trimmingCharacters(in: .whitespaces)) == "herdr"
                else { return nil }
                return pid
            }
    }

    /// The full argument vector of one process. `comm` alone cannot tell a server from a client.
    static func arguments(ofPID pid: Int32) -> String {
        TerminalJumper.runProcess("/bin/ps", args: ["-p", "\(pid)", "-o", "command="])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
