import AgentNotchCore
import AppKit
import Foundation

/// Selects the cmux pane a session runs in, so activating cmux lands on that session.
///
/// cmux stacks many panes and workspaces inside one window, which leaves it with the same problem
/// tmux has: activating the app returns to whichever pane was focused last, not to the one the
/// session is in. The fix is the same too — select the pane first, then activate.
///
/// The mapping comes from two halves cmux publishes itself. It injects `CMUX_SURFACE_ID` into every
/// pane's PTY environment, which the session's own process inherits, and it exposes that exact
/// identifier as the `id` of a `terminal` in its scripting dictionary. Reading the variable
/// therefore names the pane to focus.
///
/// The socket CLI cmux also ships would be the more direct route, and it refuses every caller that
/// was not started inside cmux; Apple events are the interface it leaves open to us.
@MainActor
enum CmuxPaneJumper {
    /// cmux keeps this identifier however it was installed.
    ///
    /// Both constants stay off the main actor so that `TerminalJumper`, which is not actor-isolated,
    /// can name cmux in its own table of supported terminals.
    nonisolated static let bundleIdentifier = "com.cmuxterm.app"

    /// The variable cmux injects into each pane. `CMUX_PANEL_ID` currently carries the same value,
    /// but the scripting dictionary addresses panes as surfaces, so that is the half to read.
    nonisolated static let surfaceEnvironmentKey = "CMUX_SURFACE_ID"

    typealias EnvironmentReader = (Int32) -> [String: String]?
    typealias ParentResolver = (Int32) -> Int32
    typealias ScriptRunner = (String) -> Bool

    static func isCmux(_ app: NSRunningApplication) -> Bool {
        isCmux(bundleIdentifier: app.bundleIdentifier)
    }

    static func isCmux(bundleIdentifier candidate: String?) -> Bool {
        candidate?.lowercased() == bundleIdentifier
    }

    /// Focuses the pane that owns `pid`. Returns false when the pane cannot be named or the script
    /// does not run, which leaves the caller with a plain app activation — the pane the user was
    /// last in, rather than no jump at all.
    @discardableResult
    static func focusPane(
        forProcessTree pid: Int32,
        environmentOf readEnvironment: EnvironmentReader = {
            ProcessEnvironment.environment(ofPID: $0)
        },
        parentOf resolveParent: ParentResolver = { TerminalJumper.parentPIDOf($0) },
        isAutomationPermitted permitted: () -> Bool = { isAutomationPermitted() },
        runScript: ScriptRunner = { runAppleScript($0) }
    ) -> Bool {
        guard
            let surfaceId = surfaceIdentifier(
                forProcessTree: pid,
                environmentOf: readEnvironment,
                parentOf: resolveParent
            )
        else {
            Log.terminal.info("cmux: no \(surfaceEnvironmentKey) above PID \(pid)")
            return false
        }
        guard let script = focusScript(surfaceId: surfaceId) else {
            Log.terminal.error("cmux: surface identifier is not a UUID")
            return false
        }
        guard permitted() else {
            Log.terminal.info("cmux: automation denied, activating the app only")
            return false
        }

        guard runScript(script) else { return false }
        Log.terminal.info("cmux surface \(surfaceId) focused")
        return true
    }

    /// Walks up from `pid` until a process carries the surface variable.
    ///
    /// The session's own process almost always has it, since cmux injects it into the pane's shell
    /// and every child inherits it. The walk covers the cases where the anchor is further from the
    /// pane — a tmux client, or a process picked off the TTY. It terminates at cmux itself, which
    /// runs without the variable.
    static func surfaceIdentifier(
        forProcessTree pid: Int32,
        environmentOf readEnvironment: EnvironmentReader,
        parentOf resolveParent: ParentResolver,
        maximumDepth: Int = 15
    ) -> String? {
        var currentPID = pid
        for _ in 0..<maximumDepth {
            if let surfaceId = readEnvironment(currentPID)?[surfaceEnvironmentKey],
                !surfaceId.isEmpty
            {
                return surfaceId
            }
            let parent = resolveParent(currentPID)
            if parent <= 1 { return nil }
            currentPID = parent
        }
        return nil
    }

    /// Builds the focus script, accepting nothing but a plain UUID.
    ///
    /// The identifier is interpolated into an AppleScript string literal, so a value carrying a
    /// quote could rewrite the statement around it. cmux only ever issues UUIDs, and requiring one
    /// leaves no character that would need escaping.
    static func focusScript(surfaceId: String) -> String? {
        guard UUID(uuidString: surfaceId) != nil else { return nil }
        return "tell application id \"\(bundleIdentifier)\" to focus terminal id \"\(surfaceId)\""
    }

    /// Whether macOS currently lets this app send Apple events to cmux.
    ///
    /// Only an outright denial counts as a stop. An undecided state is what a first jump is for:
    /// running the script is what raises the consent prompt, and refusing to run it would leave
    /// the user with no way to ever grant the permission.
    private static func isAutomationPermitted() -> Bool {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier).aeDesc else {
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
            Log.terminal.error("cmux focus script failed: \(message)")
            return false
        }
        return true
    }
}
