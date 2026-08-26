import Testing

@testable import AgentNotchCore

@Suite("Session status semantics")
struct SessionStatusTests {
    @Test(
        "Status activity semantics stay stable",
        arguments: [
            (.starting, false, false),
            (.idle, false, false),
            (.thinking, true, true),
            (.toolRunning, true, true),
            (.subagentRunning, true, true),
            (.permissionWaiting, false, true),
            (.compacting, true, true),
            (.done, false, true),
            (.error, false, true),
            (.completed, false, false),
        ] as [(SessionStatus, Bool, Bool)]
    )
    func activitySemantics(
        status: SessionStatus,
        isRunning: Bool,
        isActive: Bool
    ) {
        #expect(status.isRunning == isRunning)
        #expect(status.isActive == isActive)
    }

    @Test("Urgency ranks every status from approval through completion")
    func urgencyOrdering() {
        let ordered: [SessionStatus] = [
            .permissionWaiting,
            .error,
            .toolRunning,
            .thinking,
            .subagentRunning,
            .compacting,
            .done,
            .idle,
            .starting,
            .completed,
        ]

        #expect(ordered.map(\.urgencyRank) == Array(0...9))
    }

    @Test(
        "Agent display names remain suitable for user-facing labels",
        arguments: [
            (.claudeCode, "Claude Code"),
            (.codex, "Codex"),
            (.geminiCLI, "Gemini CLI"),
            (.custom, "Custom"),
        ] as [(AgentType, String)]
    )
    func agentDisplayNames(agentType: AgentType, expected: String) {
        #expect(agentType.displayName == expected)
    }
}
