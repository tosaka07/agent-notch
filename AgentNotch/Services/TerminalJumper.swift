import AgentNotchCore
import AppKit
import Foundation

/// Activates the terminal window running a given Claude session.
/// Handles direct terminal processes, tmux sessions (switch-client + select-window + select-pane),
/// herdr panes (see `HerdrPaneJumper`), and cmux panes (see `CmuxPaneJumper`).
enum TerminalJumper {
    private static let supportedTerminalBundleIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp-stable",
        "dev.warp.warp-preview",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.wezfurlong.wezterm",
        CmuxPaneJumper.bundleIdentifier,
    ]

    private static let supportedTerminalApplicationNames: Set<String> = [
        "terminal",
        "iterm2",
        "ghostty",
        "warp",
        "alacritty",
        "kitty",
        "wezterm",
        "cmux",
    ]

    @discardableResult
    @MainActor
    static func jump(pid: Int32?, tty: String?) -> Bool {
        Log.terminal.info("jump pid=\(pid.map(String.init) ?? "nil") tty=\(tty ?? "nil")")

        // Strategy 1: PID tree walk (non-tmux)
        if let pid, let app = findTerminalApp(forChildPID: pid) {
            Log.terminal.info("PID tree → \(app.localizedName ?? "?") (\(app.processIdentifier))")
            return activateTerminalApp(app, paneAnchorPID: pid)
        }

        // Strategy 2: TTY → tmux resolution → switch-client + select + activate
        if let tty {
            if let tmuxInfo = tmuxResolve(paneTTY: tty) {
                Log.terminal.info("tmux pane=\(tmuxInfo.paneTarget) clientPID=\(tmuxInfo.clientPID)")
                selectTmuxPane(target: tmuxInfo.paneTarget)
                if let app = findTerminalApp(forChildPID: tmuxInfo.clientPID) {
                    Log.terminal.info("tmux client → \(app.localizedName ?? "?") (\(app.processIdentifier))")
                    // The tmux client is the process cmux started, so it carries the pane's
                    // environment even though the session's own TTY belongs to the tmux server.
                    return activateTerminalApp(app, paneAnchorPID: tmuxInfo.clientPID)
                }
                Log.terminal.error("tmux client PID \(tmuxInfo.clientPID): no GUI app found")
                // The tmux client's own environment is the live one. Panes inherit theirs from the
                // tmux server, which was started by whichever client came first, so the session's
                // copy of the herdr pane variable can name a pane the user has long left.
                if let jumped = jumpThroughHerdr(anchorPID: tmuxInfo.clientPID) { return jumped }
            }

            // Fallback: direct TTY lookup
            let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            if let pids = pidsForTTY(ttyName) {
                for p in pids {
                    if let app = findTerminalApp(forChildPID: p) {
                        Log.terminal.info(
                            "TTY fallback → \(app.localizedName ?? "?") (\(app.processIdentifier))")
                        return activateTerminalApp(app, paneAnchorPID: p)
                    }
                }
            }
        }

        // Strategy 3: herdr. Its server owns the pane processes and is reparented to launchd the
        // first time the client detaches, so from then on no walk that starts at the session reaches
        // a GUI application at all. herdr's socket names the pane; the client draws it.
        for anchor in herdrAnchorCandidates(pid: pid, tty: tty) {
            if let jumped = jumpThroughHerdr(anchorPID: anchor) { return jumped }
        }

        Log.terminal.error("all strategies failed")
        return false
    }

    /// Focuses the herdr pane holding `anchorPID` and activates the terminal its client runs in.
    ///
    /// Returns nil when the anchor is not inside herdr, leaving the caller its other strategies, and
    /// false when it is but no attached client resolves to an application — a server nobody is
    /// looking at. The pane stays focused in that case, so the next attach opens on it.
    @MainActor
    private static func jumpThroughHerdr(anchorPID: Int32) -> Bool? {
        guard let location = HerdrPaneJumper.location(forProcessTree: anchorPID) else { return nil }
        Log.terminal.info("herdr pane=\(location.paneId) socket=\(location.socketPath)")
        HerdrPaneJumper.focusPane(location)

        for clientPID in HerdrPaneJumper.clientPIDs(forSocketPath: location.socketPath) {
            if let app = findTerminalApp(forChildPID: clientPID) {
                Log.terminal.info(
                    "herdr client → \(app.localizedName ?? "?") (\(app.processIdentifier))")
                return activateTerminalApp(app, paneAnchorPID: clientPID)
            }
        }
        Log.terminal.error("herdr: no attached client resolves to a terminal app")
        return false
    }

    /// The processes worth asking herdr about: the session's own, then whatever holds its TTY.
    private static func herdrAnchorCandidates(pid: Int32?, tty: String?) -> [Int32] {
        var anchors: [Int32] = []
        if let pid { anchors.append(pid) }
        if let tty {
            let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            anchors.append(contentsOf: (pidsForTTY(ttyName) ?? []).filter { $0 != pid })
        }
        return anchors
    }

    /// Activating an app lands on the window and pane it left off in, which is the whole answer for
    /// a terminal that gives each session its own window. A multiplexer sharing one window does not:
    /// the session's own pane is selected first — herdr over its socket, cmux over Apple events —
    /// the same extra step tmux needs. A failed selection still activates, leaving the user in the
    /// terminal rather than nowhere.
    @MainActor
    private static func activateTerminalApp(
        _ app: NSRunningApplication,
        paneAnchorPID: Int32?
    ) -> Bool {
        if let paneAnchorPID {
            if let location = HerdrPaneJumper.location(forProcessTree: paneAnchorPID) {
                HerdrPaneJumper.focusPane(location)
            }
            if CmuxPaneJumper.isCmux(app) {
                CmuxPaneJumper.focusPane(forProcessTree: paneAnchorPID)
            }
        }
        return completeActivation(accepted: app.activate(), onActivated: closeNotch)
    }

    static func completeActivation(
        accepted: Bool,
        onActivated: () -> Void
    ) -> Bool {
        guard accepted else {
            Log.terminal.error("terminal app rejected activation")
            return false
        }
        onActivated()
        return true
    }

    private static func closeNotch() {
        NotificationCenter.default.post(name: .agentNotchClosePanel, object: nil)
    }

    // MARK: - Terminal Info Resolution

    struct TerminalInfo {
        let appName: String  // e.g. "iTerm2"
        let appIcon: NSImage?  // app icon
        let tmuxTarget: String?  // e.g. "main:2.1" or nil
        let herdrPaneTarget: String?  // e.g. "w6:p2" or nil

        init(
            appName: String,
            appIcon: NSImage?,
            tmuxTarget: String?,
            herdrPaneTarget: String? = nil
        ) {
            self.appName = appName
            self.appIcon = appIcon
            self.tmuxTarget = tmuxTarget
            self.herdrPaneTarget = herdrPaneTarget
        }
    }

    /// Resolve terminal app and multiplexer info for a session. Call once and cache results.
    @MainActor
    static func resolveTerminalInfo(pid: Int32?, tty: String?) -> TerminalInfo? {
        // Try PID tree first
        if let pid, let app = findTerminalApp(forChildPID: pid) {
            let tmux = tty.flatMap { tmuxResolve(paneTTY: $0) }
            return TerminalInfo(
                appName: app.localizedName ?? "Terminal",
                appIcon: app.icon,
                tmuxTarget: tmux?.paneTarget,
                herdrPaneTarget: ownHerdrPaneId(of: pid)
            )
        }

        // Try TTY → tmux
        if let tty, let tmux = tmuxResolve(paneTTY: tty) {
            if let app = findTerminalApp(forChildPID: tmux.clientPID) {
                return TerminalInfo(
                    appName: app.localizedName ?? "Terminal",
                    appIcon: app.icon,
                    tmuxTarget: tmux.paneTarget,
                    herdrPaneTarget: ownHerdrPaneId(of: tmux.clientPID)
                )
            }
            if let info = resolveHerdrTerminalInfo(
                anchorPID: tmux.clientPID,
                tmuxTarget: tmux.paneTarget
            ) {
                return info
            }
        }

        // TTY fallback
        if let tty {
            let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            if let pids = pidsForTTY(ttyName) {
                for p in pids {
                    if let app = findTerminalApp(forChildPID: p) {
                        return TerminalInfo(
                            appName: app.localizedName ?? "Terminal",
                            appIcon: app.icon,
                            tmuxTarget: nil,
                            herdrPaneTarget: ownHerdrPaneId(of: p)
                        )
                    }
                }
            }
        }

        // herdr, whose detached server hides the terminal from every walk above
        for anchor in herdrAnchorCandidates(pid: pid, tty: tty) {
            if let info = resolveHerdrTerminalInfo(anchorPID: anchor, tmuxTarget: nil) {
                return info
            }
        }

        return nil
    }

    /// Names the terminal drawing the herdr pane `anchorPID` sits in, once herdr confirms it still
    /// holds that pane.
    ///
    /// An inherited pane identifier is display history: the pane is gone after a server restart, or
    /// after being closed while the process it held lived on. Confirming it keeps a stale value from
    /// being offered as a destination — the same reason `TerminalInfoResolver` revalidates at all.
    @MainActor
    private static func resolveHerdrTerminalInfo(
        anchorPID: Int32,
        tmuxTarget: String?
    ) -> TerminalInfo? {
        guard let location = HerdrPaneJumper.location(forProcessTree: anchorPID),
            HerdrPaneJumper.paneExists(location)
        else { return nil }

        for clientPID in HerdrPaneJumper.clientPIDs(forSocketPath: location.socketPath) {
            if let app = findTerminalApp(forChildPID: clientPID) {
                return TerminalInfo(
                    appName: app.localizedName ?? "Terminal",
                    appIcon: app.icon,
                    tmuxTarget: tmuxTarget,
                    herdrPaneTarget: location.paneId
                )
            }
        }
        return nil
    }

    /// The pane variable on one process, without the walk `jumpThroughHerdr` pays for. A terminal
    /// that was already found needs no help locating herdr — the identifier is recorded for display.
    private static func ownHerdrPaneId(of pid: Int32) -> String? {
        HerdrPaneJumper.location(forProcessTree: pid, maximumDepth: 1)?.paneId
    }

    // Icon is now cached on UnifiedSession.terminalAppIcon via resolveTerminalInfo()

    // MARK: - PID tree walk

    private static func findTerminalApp(forChildPID childPID: Int32) -> NSRunningApplication? {
        let appPIDs = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications
                .filter {
                    $0.activationPolicy == .regular
                        && isSupportedTerminalApplication(
                            bundleIdentifier: $0.bundleIdentifier,
                            localizedName: $0.localizedName
                        )
                }
                .map { ($0.processIdentifier, $0) }
        )
        var currentPID = childPID
        for _ in 0..<15 {
            if let app = appPIDs[currentPID] { return app }
            let parent = parentPIDOf(currentPID)
            if parent <= 1 { break }
            currentPID = parent
        }
        return nil
    }

    static func isSupportedTerminalApplication(
        bundleIdentifier: String?,
        localizedName: String?
    ) -> Bool {
        if let bundleIdentifier,
            supportedTerminalBundleIdentifiers.contains(bundleIdentifier.lowercased())
        {
            return true
        }
        if let localizedName,
            supportedTerminalApplicationNames.contains(localizedName.lowercased())
        {
            return true
        }
        return false
    }

    // MARK: - tmux

    private struct TmuxInfo {
        let paneTarget: String  // e.g. "session:2.3"
        let clientPID: Int32
    }

    private static func tmuxResolve(paneTTY tty: String) -> TmuxInfo? {
        let panes = runTmux([
            "list-panes", "-a",
            "-F", "#{pane_tty} #{session_name}:#{window_index}.#{pane_index}",
        ])
        guard
            let targetLine = panes.split(separator: "\n")
                .first(where: { $0.hasPrefix(tty) })
        else { return nil }

        let paneTarget = targetLine.split(separator: " ").last.map(String.init) ?? ""
        let sessionName = paneTarget.split(separator: ":").first.map(String.init) ?? ""

        let clients = runTmux([
            "list-clients",
            "-F", "#{client_tty} #{client_pid} #{client_session}",
        ])
        // Prefer client already attached to the same session
        for line in clients.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            if String(parts[2]) == sessionName, let pid = Int32(parts[1]) {
                return TmuxInfo(paneTarget: paneTarget, clientPID: pid)
            }
        }
        // Fallback: any client
        if let firstLine = clients.split(separator: "\n").first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2, let pid = Int32(parts[1]) {
                return TmuxInfo(paneTarget: paneTarget, clientPID: pid)
            }
        }
        return nil
    }

    private static func selectTmuxPane(target: String) {
        let sessionName = target.split(separator: ":").first.map(String.init) ?? ""
        let parts = target.split(separator: ".")
        let windowTarget = String(parts.first ?? Substring(target))

        _ = runTmux(["switch-client", "-t", sessionName])
        _ = runTmux(["select-window", "-t", windowTarget])
        _ = runTmux(["select-pane", "-t", target])
    }

    // MARK: - tmux path resolution

    private static let tmuxPath: String? = {
        // Resolve via login shell first (handles Nix, asdf, etc.)
        let shellResolved = runProcess("/bin/sh", args: ["-l", "-c", "which tmux"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !shellResolved.isEmpty, FileManager.default.isExecutableFile(atPath: shellResolved) {
            return shellResolved
        }
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static func runTmux(_ args: [String]) -> String {
        guard let tmux = tmuxPath else { return "" }
        return runProcess(tmux, args: args)
    }

    // MARK: - Helpers

    private static func pidsForTTY(_ ttyName: String) -> [Int32]? {
        let output = runProcess("/bin/ps", args: ["-t", ttyName, "-o", "pid="])
        let pids = output.split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        return pids.isEmpty ? nil : pids
    }

    /// Shared with `CmuxPaneJumper`, which walks the same tree for the pane environment.
    static func parentPIDOf(_ pid: Int32) -> Int32 {
        let output = runProcess("/bin/ps", args: ["-p", "\(pid)", "-o", "ppid="])
        return Int32(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Shared with `HerdrPaneJumper`, which reads the process table through the same `ps` calls.
    static func runProcess(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
