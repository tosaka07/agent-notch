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

    /// How many trailing path components of the working directory can name the workspace.
    ///
    /// One covers a session started at the workspace root, which is the common case. Going a little
    /// further covers a run started inside a package of a monorepo, where the root is an ancestor
    /// of the working directory. Beyond that the components get generic enough — `src`, `projects`,
    /// a home directory name — that a match stops being evidence of the right window.
    nonisolated static let maximumWorkspaceCandidates = 3

    /// What VS Code puts between the active editor and the workspace root in a window title.
    nonisolated static let titleSeparator = " — "

    typealias EnvironmentReader = (Int32) -> [String: String]?
    typealias ParentResolver = (Int32) -> Int32
    typealias ScriptRunner = (String) -> String?

    static func isVSCodeFamily(_ app: NSRunningApplication) -> Bool {
        isVSCodeFamily(bundleIdentifier: app.bundleIdentifier)
    }

    static func isVSCodeFamily(bundleIdentifier candidate: String?) -> Bool {
        guard let candidate else { return false }
        return bundleIdentifiers.contains(candidate.lowercased())
    }

    /// Raises the window that owns `pid`. Returns false when the workspace names no window, or
    /// names more than one, which leaves the caller with a plain app activation — the window the
    /// user was last in, rather than the wrong one.
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
        guard !workspaceCandidates(forWorkingDirectory: directory).isEmpty else {
            Log.terminal.info("vscode: no workspace name in \(directory)")
            return false
        }
        guard permitted() else {
            Log.terminal.info("vscode: automation denied, activating the app only")
            return false
        }

        guard let listed = runScript(windowTitleScript(applicationPID: applicationPID)) else {
            return false
        }
        guard
            let title = windowTitle(
                forWorkingDirectory: directory,
                titles: windowTitles(fromScriptResult: listed)
            )
        else {
            Log.terminal.info("vscode: no single window titled after \(directory)")
            return false
        }
        guard let script = focusScript(applicationPID: applicationPID, windowTitle: title),
            runScript(script) != nil
        else {
            return false
        }

        Log.terminal.info("vscode window \(title) raised")
        return true
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

    /// The workspace names the working directory could belong to, deepest path component first.
    static func workspaceCandidates(forWorkingDirectory directory: String) -> [String] {
        directory.split(separator: "/")
            .map(String.init)
            .reversed()
            .prefix(maximumWorkspaceCandidates)
            .map { $0 }
    }

    /// The root a window title names, which is the part after the last separator.
    ///
    /// A title reads `activeEditor — root` by default, and drops to just `root` when the window has
    /// no editor open. The active editor is the half that changes as the user works, so only the
    /// root is ever matched against.
    static func workspaceRoot(ofWindowTitle title: String) -> String {
        let root = title.components(separatedBy: titleSeparator).last ?? title
        return root.trimmingCharacters(in: .whitespaces)
    }

    /// The title of the one window this working directory belongs to, if exactly one does.
    ///
    /// The match is on whole path components rather than on substrings, and it is abandoned when
    /// more than one window answers to it. A session in `agent-notch/packages/core` alongside an
    /// unrelated window rooted at some other `core` is a case where nothing here can tell the two
    /// apart, and raising the wrong window is worse than raising none: the caller's activation
    /// still lands the user in the editor, where the previous behaviour left them anyway.
    static func windowTitle(forWorkingDirectory directory: String, titles: [String]) -> String? {
        let candidates = Set(workspaceCandidates(forWorkingDirectory: directory))
        let matches = titles.filter { candidates.contains(workspaceRoot(ofWindowTitle: $0)) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Splits the listing script's result, dropping the blank entry its trailing newline leaves.
    static func windowTitles(fromScriptResult result: String) -> [String] {
        result.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Builds the script that reports what the editor's windows are titled.
    ///
    /// The process is addressed by its Unix ID rather than by name so that two editors of the same
    /// family, or a second app that happens to be called `Code`, cannot answer instead.
    static func windowTitleScript(applicationPID: Int32) -> String {
        """
        tell application "System Events" to tell (first process whose unix id is \(applicationPID))
        set titles to ""
        repeat with candidate in windows
        set titles to titles & (name of candidate) & linefeed
        end repeat
        end tell
        return titles
        """
    }

    /// Builds the raise script, which fails when the title no longer names a window.
    ///
    /// The title is interpolated into an AppleScript string literal, so one carrying a quote or a
    /// backslash could rewrite the statement around it. Both are escaped; a title carrying a line
    /// break is refused outright, since the listing that produced it is newline-separated and could
    /// not have reported such a title in one piece anyway.
    static func focusScript(applicationPID: Int32, windowTitle title: String) -> String? {
        guard !title.isEmpty, title.rangeOfCharacter(from: .newlines) == nil else { return nil }

        let escaped =
            title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
            tell application "System Events" to tell (first process whose unix id is \
            \(applicationPID))
            perform action "AXRaise" of (first window whose name is "\(escaped)")
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

    /// Runs a script and returns what it produced, or nil when it did not run.
    ///
    /// A script that returns nothing still answers with an empty string, so nil never stands for a
    /// successful run with no result.
    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            Log.terminal.info("vscode script did not apply: \(message)")
            return nil
        }
        return result.stringValue ?? ""
    }
}
