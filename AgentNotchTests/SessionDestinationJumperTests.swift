import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Primary session destination")
@MainActor
struct SessionDestinationJumperTests {
    @Test("A session with no reachable surface has no destination")
    func noDestination() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)

        #expect(destination(for: session) == nil)
    }

    @Test("A desktop-run session opens in the Claude app")
    func claudeAppDestination() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)

        #expect(destination(for: session, canJumpToClaudeApp: true) == .claudeApp)
    }

    @Test("A verified terminal outranks the Claude app")
    func terminalOutranksClaudeApp() {
        let session = makeTerminalSession()

        #expect(destination(for: session, canJumpToClaudeApp: true) == .terminal)
    }

    @Test("The Codex app outranks every other surface")
    func codexAppOutranksEverything() {
        let session = makeTerminalSession(agentType: .codex)

        #expect(
            destination(for: session, canJumpToCodexApp: true, canJumpToClaudeApp: true)
                == .codexApp
        )
    }

    @Test("Each destination routes to its own jump")
    func jumpRoutesToTheChosenDestination() {
        let claudeSession = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        var jumped: [String] = []

        #expect(jump(claudeSession, canJumpToClaudeApp: true, record: { jumped.append($0) }))
        #expect(jumped == ["claude"])

        jumped = []
        #expect(jump(makeTerminalSession(), record: { jumped.append($0) }))
        #expect(jumped == ["terminal"])

        jumped = []
        #expect(
            jump(
                makeTerminalSession(agentType: .codex),
                canJumpToCodexApp: true,
                record: { jumped.append($0) }
            )
        )
        #expect(jumped == ["codex"])
    }

    @Test("With no destination, nothing is opened")
    func jumpWithoutDestinationDoesNothing() {
        var jumped: [String] = []

        #expect(
            jump(
                UnifiedSession(id: "cli-1", agentType: .claudeCode),
                record: { jumped.append($0) }
            ) == false
        )
        #expect(jumped.isEmpty)
    }

    // MARK: - Helpers

    private func destination(
        for session: UnifiedSession,
        canJumpToCodexApp: Bool = false,
        canJumpToClaudeApp: Bool = false
    ) -> SessionDestinationJumper.Destination? {
        SessionDestinationJumper.destination(
            for: session,
            canJumpToCodexApp: { _ in canJumpToCodexApp },
            canJumpToClaudeApp: { _ in canJumpToClaudeApp }
        )
    }

    private func jump(
        _ session: UnifiedSession,
        canJumpToCodexApp: Bool = false,
        canJumpToClaudeApp: Bool = false,
        record: @escaping (String) -> Void
    ) -> Bool {
        SessionDestinationJumper.jump(
            to: session,
            canJumpToCodexApp: { _ in canJumpToCodexApp },
            jumpToCodexApp: { _ in
                record("codex")
                return true
            },
            jumpToTerminal: { _, _ in
                record("terminal")
                return true
            },
            canJumpToClaudeApp: { _ in canJumpToClaudeApp },
            jumpToClaudeApp: { _ in
                record("claude")
                return true
            }
        )
    }

    /// The state `isTerminalJumpAvailable` requires: a live runtime resolved to a real app.
    private func makeTerminalSession(agentType: AgentType = .claudeCode) -> UnifiedSession {
        let session = UnifiedSession(id: "cli-1", agentType: agentType)
        session.pid = 12_345
        session.terminalInfoResolved = true
        session.terminalAppName = "Terminal"
        return session
    }
}
