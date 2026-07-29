import AgentNotchCore

/// Opens the primary interactive surface represented by a session card.
///
/// This is intentionally separate from the configurable global "Jump to terminal"
/// action: the local `t` shortcut invokes the same primary destination shown on
/// the card — an exact Codex App thread when available, otherwise a verified terminal,
/// otherwise the Claude desktop app session that owns this run.
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

    /// A verified terminal outranks the Claude desktop app on purpose. A desktop-run session has no
    /// terminal to activate, so the two are mutually exclusive in practice; where both do resolve —
    /// a terminal session whose transcript was also imported into the app — the live terminal is
    /// where the user's own run is.
    static func destination(
        for session: UnifiedSession,
        canJumpToCodexApp: CodexAvailability = { CodexAppJumper.canJump(to: $0) },
        canJumpToClaudeApp: ClaudeAvailability = { ClaudeDesktopJumper.canJump(to: $0) }
    ) -> Destination? {
        if canJumpToCodexApp(session) {
            return .codexApp
        }
        if session.isTerminalJumpAvailable {
            return .terminal
        }
        if canJumpToClaudeApp(session) {
            return .claudeApp
        }
        return nil
    }
}
