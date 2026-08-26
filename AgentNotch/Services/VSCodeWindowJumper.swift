import AgentNotchCore
import AppKit
import Foundation

/// Raises the VS Code window whose workspace a session runs in, so activating the editor lands on
/// that window rather than whichever one was focused last.
///
/// VS Code has the same problem cmux does — many sessions live inside one app — but it does not
/// hand out an identifier for the surface that owns a process. Its terminals are all children of a
/// single `ptyHost` utility process, which is shared across every window, so the process tree names
/// the app and stops there.
///
/// What is left is the workspace. The editor titles each window after its root folder by default,
/// and it starts integrated terminals in that folder, so the working directory a session inherited
/// names the window to raise. That is a match on a display string rather than on an identifier the
/// editor issued: a renamed title, a multi-root workspace, or two windows on folders of the same
/// name can all miss. A miss is not a failure — the caller still activates the app, which is where
/// the jump used to end for every VS Code session.
@MainActor
enum VSCodeWindowJumper {
    /// The VS Code family, by bundle identifier. Forks ship the same window titling and the same
    /// shared-`ptyHost` layout, so one table covers them.
    ///
    /// Kept off the main actor so `TerminalJumper`, which is not actor-isolated, can name these in
    /// its own table of supported terminals.
    nonisolated static let bundleIdentifiers: Set<String> = [
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.microsoft.vscodeexploration",
        "com.vscodium",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
    ]

    /// The variable a shell exports for its working directory. Every VS Code integrated terminal
    /// starts in the window's workspace folder, so this is where the workspace name comes from.
    nonisolated static let workingDirectoryEnvironmentKey = "PWD"

    /// How many trailing path components of the working directory are offered to the title match.
    ///
    /// One covers a session started at the workspace root, which is the common case. Going a little
    /// further covers a run started inside a package of a monorepo, where the root is an ancestor
    /// of the working directory. Beyond that the components get generic enough — `src`, `projects`,
    /// a home directory name — that a match stops being evidence of the right window.
    nonisolated static let maximumWorkspaceCandidates = 3

    typealias EnvironmentReader = (Int32) -> [String: String]?
    typealias ParentResolver = (Int32) -> Int32
    typealias ScriptRunner = (String) -> Bool

    static func isVSCodeFamily(_ app: NSRunningApplication) -> Bool {
        isVSCodeFamily(bundleIdentifier: app.bundleIdentifier)
    }

    static func isVSCodeFamily(bundleIdentifier candidate: String?) -> Bool {
        guard let candidate else { return false }
        return bundleIdentifiers.contains(candidate.lowercased())
    }

    /// Raises the window that owns `pid`. Returns false when no candidate names a window, which
    /// leaves the caller with a plain app activation — the window the user was last in, rather than
    /// no jump at all.
    @discardableResult
    static func focusWindow(
        forProcessTree pid: Int32,
        applicationPID: Int32,
        environmentOf readEnvironment: EnvironmentReader = {
            ProcessEnvironment.environment(ofPID: $0)
        },
        parentOf resolveParent: ParentResolver = { TerminalJumper.parentPIDOf($0) },
        isAutomationPermitted permitted: () -> Bool = { isAutomationPermitted() },
        runScript: ScriptRunner = { runAppleScript($0) }
    ) -> Bool {
        guard
            let directory = workingDirectory(
                forProcessTree: pid,
                environmentOf: readEnvironment,
                parentOf: resolveParent
            )
        else {
            Log.terminal.info("vscode: no \(workingDirectoryEnvironmentKey) above PID \(pid)")
            return false
        }

        let candidates = workspaceCandidates(forWorkingDirectory: directory)
        guard !candidates.isEmpty else {
            Log.terminal.info("vscode: no workspace name in \(directory)")
            return false
        }
        guard permitted() else {
            Log.terminal.info("vscode: automation denied, activating the app only")
            return false
        }

        // Nearest component first: the deepest one that names a window is the most specific match.
        for candidate in candidates {
            guard
                let script = focusScript(applicationPID: applicationPID, workspaceName: candidate)
            else { continue }
            if runScript(script) {
                Log.terminal.info("vscode window for workspace \(candidate) raised")
                return true
            }
        }

        Log.terminal.info("vscode: no window titled after \(directory)")
        return false
    }

    /// Walks up from `pid` until a process carries a working directory.
    ///
    /// The session's own process almost always has one, since the shell VS Code started exports it
    /// and every child inherits it. The walk covers the anchors that sit further from the shell.
    static func workingDirectory(
        forProcessTree pid: Int32,
        environmentOf readEnvironment: EnvironmentReader,
        parentOf resolveParent: ParentResolver,
        maximumDepth: Int = 15
    ) -> String? {
        var currentPID = pid
        for _ in 0..<maximumDepth {
            if let directory = readEnvironment(currentPID)?[workingDirectoryEnvironmentKey],
                directory.hasPrefix("/")
            {
                return directory
            }
            let parent = resolveParent(currentPID)
            if parent <= 1 { return nil }
            currentPID = parent
        }
        return nil
    }

    /// The window names to try, deepest path component first.
    static func workspaceCandidates(forWorkingDirectory directory: String) -> [String] {
        directory.split(separator: "/")
            .map(String.init)
            .reversed()
            .prefix(maximumWorkspaceCandidates)
            .map { $0 }
    }

    /// Builds the raise script, which fails when the workspace names no window.
    ///
    /// The name is interpolated into an AppleScript string literal, so a directory carrying a quote
    /// or a backslash could rewrite the statement around it. Both are escaped; a name carrying a
    /// line break is refused outright, since nothing a real window is titled after needs one.
    ///
    /// The process is addressed by its Unix ID rather than by name so that two editors of the same
    /// family, or a second app that happens to be called `Code`, cannot receive the raise.
    static func focusScript(applicationPID: Int32, workspaceName: String) -> String? {
        guard !workspaceName.isEmpty,
            workspaceName.rangeOfCharacter(from: .newlines) == nil
        else {
            return nil
        }

        let escaped =
            workspaceName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
            tell application "System Events" to tell (first process whose unix id is \
            \(applicationPID))
            set matches to (every window whose name contains "\(escaped)")
            if matches is {} then error "no window for this workspace"
            perform action "AXRaise" of item 1 of matches
            end tell
            """
    }

    /// Whether macOS currently lets this app drive System Events.
    ///
    /// The raise goes through System Events rather than the accessibility API directly, so the
    /// permission this needs is the automation consent the app already asks for elsewhere, not a
    /// second grant in Accessibility. Only an outright denial counts as a stop: an undecided state
    /// is what a first jump is for, since running the script is what raises the consent prompt.
    private static func isAutomationPermitted() -> Bool {
        guard
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents").aeDesc
        else {
            return true
        }
        let status = AEDeterminePermissionToAutomateTarget(
            target,
            typeWildCard,
            typeWildCard,
            false
        )
        return status != errAEEventNotPermitted
    }

    private static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            Log.terminal.info("vscode raise script did not apply: \(message)")
            return false
        }
        return true
    }
}
