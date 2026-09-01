import AgentNotchCore

/// Opens the primary interactive surface represented by a session card.
///
/// This is intentionally separate from the configurable global "Jump to terminal"
/// action: the local `t` shortcut invokes the same primary destination shown on
/// the card — the verified terminal the run lives in when there is one, otherwise the exact
/// Codex App thread, otherwise the Claude desktop app session that owns this run.
@MainActor
enum SessionDestinationJumper {
    enum Destination: Equatable {
        case codexApp
        case terminal
        case claudeApp
    }

    typealias CodexAvailability = @MainActor (UnifiedSession) -> Bool
    typealias CodexJump = @MainActor (UnifiedSession) -> Bool
    typealias TerminalJump = @MainActor (_ pid: Int32?, _ tty: String?) -> Bool
    typealias ClaudeAvailability = @MainActor (UnifiedSession) -> Bool
    typealias ClaudeJump = @MainActor (UnifiedSession) -> Bool

    @discardableResult
    static func jump(
        to session: UnifiedSession,
        canJumpToCodexApp: CodexAvailability = { CodexAppJumper.canJump(to: $0) },
        jumpToCodexApp: CodexJump = { CodexAppJumper.jump(to: $0) },
        jumpToTerminal: TerminalJump = { TerminalJumper.jump(pid: $0, tty: $1) },
        canJumpToClaudeApp: ClaudeAvailability = { ClaudeDesktopJumper.canJump(to: $0) },
        jumpToClaudeApp: ClaudeJump = { ClaudeDesktopJumper.jump(to: $0) }
    ) -> Bool {
        switch destination(
            for: session,
            canJumpToCodexApp: canJumpToCodexApp,
            canJumpToClaudeApp: canJumpToClaudeApp
        ) {
        case .codexApp:
            return jumpToCodexApp(session)
        case .terminal:
            return jumpToTerminal(session.pid, session.tty)
        case .claudeApp:
            return jumpToClaudeApp(session)
        case nil:
            return false
        }
    }

    /// A verified terminal outranks both desktop apps on purpose. A desktop-run session has no
    /// terminal to activate, so the surfaces are mutually exclusive in practice; where both do
    /// resolve — a terminal session whose thread the desktop app can also open — the live terminal
    /// is where the user's own run is.
    ///
    /// This matters most for Codex: `CodexAppJumper.canJump` only asks whether macOS has an app
    /// registered for `codex://`, which ChatGPT.app claims merely by being installed. Ranking it
    /// first sent a `codex` run started in a terminal to the desktop app instead of the pane it is
    /// actually running in.
    static func destination(
        for session: UnifiedSession,
        canJumpToCodexApp: CodexAvailability = { CodexAppJumper.canJump(to: $0) },
        canJumpToClaudeApp: ClaudeAvailability = { ClaudeDesktopJumper.canJump(to: $0) }
    ) -> Destination? {
        if session.isTerminalJumpAvailable {
            return .terminal
        }
        if canJumpToCodexApp(session) {
            return .codexApp
        }
        if canJumpToClaudeApp(session) {
            return .claudeApp
        }
        return nil
    }
}
