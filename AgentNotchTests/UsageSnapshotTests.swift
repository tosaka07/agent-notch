import Testing
@testable import AgentNotchCore

@Suite("UsageSnapshot.primaryUsedPercent Tests")
struct UsageSnapshotTests {
    /// ゲージには「今いちばん気にすべき枠」を出す。session 固定だと、モデル別週次枠が
    /// session より先に上限へ当たっているケース（Fable 88% > session 86%）を見落とす。
    @Test("Claude Code picks the highest window when none is marked active")
    func claudePicksHighestWindow() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 42, resetsAt: nil),
                weekAllModels: UsageWindow(usedPercent: 78, resetsAt: nil)
            ),
            codex: nil,
            fetchedAt: .now
        )
        #expect(snapshot.primaryUsedPercent(for: .claudeCode) == 78)

        let onlyWeek = UsageSnapshot(
            claude: ClaudeUsageSnapshot(session: nil, weekAllModels: UsageWindow(usedPercent: 78, resetsAt: nil)),
            codex: nil,
            fetchedAt: .now
        )
        #expect(onlyWeek.primaryUsedPercent(for: .claudeCode) == 78)
    }

    /// API が `is_active` を返している枠があれば、使用率の高さより優先する
    /// （「今まさに効いている制限」がユーザーにとっての本当のボトルネックなので）。
    @Test("Claude Code prefers the window the API marks as active")
    func claudePrefersActiveWindow() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 95, resetsAt: nil, isActive: false),
                weekAllModels: UsageWindow(usedPercent: 20, resetsAt: nil, isActive: false),
                weekModels: [
                    ModelUsageWindow(
                        modelLabel: "Fable",
                        window: UsageWindow(usedPercent: 60, resetsAt: nil, severity: .warning, isActive: true)
                    )
                ]
            ),
            codex: nil,
            fetchedAt: .now
        )
        #expect(snapshot.primaryUsedPercent(for: .claudeCode) == 60)
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
            claude: ClaudeUsageSnapshot(session: UsageWindow(usedPercent: 90, resetsAt: nil), weekAllModels: nil),
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
