import Testing
@testable import AgentNotchCore

@Suite("UsageSnapshot.primaryUsedPercent Tests")
struct UsageSnapshotTests {
    @Test("Claude Code prefers session, falls back to weekAllModels when session is nil")
    func claudePrefersSession() {
        let withSession = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 42, resetsAt: nil),
                weekAllModels: UsageWindow(usedPercent: 78, resetsAt: nil),
                weekModel: nil,
                weekModelLabel: nil
            ),
            codex: nil,
            fetchedAt: .now
        )
        #expect(withSession.primaryUsedPercent(for: .claudeCode) == 42)

        let sessionMissing = UsageSnapshot(
            claude: ClaudeUsageSnapshot(session: nil, weekAllModels: UsageWindow(usedPercent: 78, resetsAt: nil), weekModel: nil, weekModelLabel: nil),
            codex: nil,
            fetchedAt: .now
        )
        #expect(sessionMissing.primaryUsedPercent(for: .claudeCode) == 78)
    }

    @Test("Codex prefers primary, falls back to secondary when primary is nil")
    func codexPrefersPrimary() {
        let withPrimary = UsageSnapshot(
            claude: nil,
            codex: CodexUsageSnapshot(
                primary: UsageWindow(usedPercent: 20, resetsAt: nil),
                secondary: UsageWindow(usedPercent: 55, resetsAt: nil),
                planType: "plus"
            ),
            fetchedAt: .now
        )
        #expect(withPrimary.primaryUsedPercent(for: .codex) == 20)

        let primaryMissing = UsageSnapshot(
            claude: nil,
            codex: CodexUsageSnapshot(primary: nil, secondary: UsageWindow(usedPercent: 55, resetsAt: nil), planType: nil),
            fetchedAt: .now
        )
        #expect(primaryMissing.primaryUsedPercent(for: .codex) == 55)
    }

    @Test("Gemini CLI / Custom always return nil regardless of snapshot content")
    func geminiAndCustomAlwaysNil() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(session: UsageWindow(usedPercent: 90, resetsAt: nil), weekAllModels: nil, weekModel: nil, weekModelLabel: nil),
            codex: CodexUsageSnapshot(primary: UsageWindow(usedPercent: 90, resetsAt: nil), secondary: nil, planType: nil),
            fetchedAt: .now
        )
        #expect(snapshot.primaryUsedPercent(for: .geminiCLI) == nil)
        #expect(snapshot.primaryUsedPercent(for: .custom) == nil)
    }

    @Test("Returns nil when the relevant agent has no snapshot at all")
    func nilWhenSnapshotMissing() {
        #expect(UsageSnapshot.empty.primaryUsedPercent(for: .claudeCode) == nil)
        #expect(UsageSnapshot.empty.primaryUsedPercent(for: .codex) == nil)
    }
}
