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

    // MARK: - metric による枠の選択

    /// 設定で枠を選んだら、使用率が高い枠や is_active な枠より設定を優先する
    /// （「セッションだけ見たい」という意思表示なので auto の判断で上書きしない）。
    @Test("metric selects the requested window across agents")
    func metricSelectsRequestedWindow() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 12, resetsAt: nil, isActive: true),
                weekAllModels: UsageWindow(usedPercent: 40, resetsAt: nil),
                weekModels: [
                    ModelUsageWindow(modelLabel: "Opus", window: UsageWindow(usedPercent: 66, resetsAt: nil)),
                    ModelUsageWindow(modelLabel: "Fable", window: UsageWindow(usedPercent: 88, resetsAt: nil)),
                ]
            ),
            codex: CodexUsageSnapshot(
                primary: UsageWindow(usedPercent: 20, resetsAt: nil),
                secondary: UsageWindow(usedPercent: 55, resetsAt: nil),
                planType: "pro"
            ),
            fetchedAt: .now
        )

        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .session)?.usedPercent == 12)
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .weekly)?.usedPercent == 40)
        // モデル別はいちばん高い枠（先に上限へ当たる方）を代表にする。
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .weeklyModel)?.usedPercent == 88)
        // auto は is_active を優先するので session（12%）。
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .auto)?.usedPercent == 12)

        // Codex は session → primary、weekly → secondary に対応づける。
        #expect(snapshot.primaryWindow(for: .codex, metric: .session)?.usedPercent == 20)
        #expect(snapshot.primaryWindow(for: .codex, metric: .weekly)?.usedPercent == 55)
    }

    /// 設定した枠が存在しないエージェントでゲージが消えるのは理不尽なので auto に落とす。
    @Test("metric falls back to auto when the requested window is absent")
    func metricFallsBackToAuto() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: nil,
                weekAllModels: UsageWindow(usedPercent: 40, resetsAt: nil)
            ),
            codex: CodexUsageSnapshot(
                primary: UsageWindow(usedPercent: 20, resetsAt: nil),
                secondary: nil,
                planType: nil
            ),
            fetchedAt: .now
        )

        // Claude に session 枠が無い → auto（= weekAllModels 40%）。
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .session)?.usedPercent == 40)
        // Claude にモデル別枠が無い → auto。
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .weeklyModel)?.usedPercent == 40)
        // Codex にはモデル別枠という概念が無い → auto（= primary 20%）。
        #expect(snapshot.primaryWindow(for: .codex, metric: .weeklyModel)?.usedPercent == 20)
        // Codex の secondary が無い → auto（= primary）。
        #expect(snapshot.primaryWindow(for: .codex, metric: .weekly)?.usedPercent == 20)
        // 枠が一切無いエージェントは metric を問わず nil のまま。
        #expect(UsageSnapshot.empty.primaryWindow(for: .claudeCode, metric: .session) == nil)
        #expect(snapshot.primaryWindow(for: .geminiCLI, metric: .session) == nil)
    }
}
