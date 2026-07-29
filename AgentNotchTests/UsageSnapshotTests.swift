import Testing

@testable import AgentNotchCore

@Suite("UsageSnapshot.primaryUsedPercent Tests")
struct UsageSnapshotTests {
    /// The gauge shows whichever limit matters most right now. Pinning it to the session
    /// limit would miss cases where a per-model weekly limit hits the ceiling first
    /// (Fable 88% > session 86%).
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
            claude: ClaudeUsageSnapshot(
                session: nil, weekAllModels: UsageWindow(usedPercent: 78, resetsAt: nil)),
            codex: nil,
            fetchedAt: .now
        )
        #expect(onlyWeek.primaryUsedPercent(for: .claudeCode) == 78)
    }

    /// A limit the API marks `is_active` wins over a higher-utilization one: the limit
    /// actually in force right now is the user's real bottleneck.
    @Test("Claude Code prefers the window the API marks as active")
    func claudePrefersActiveWindow() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 95, resetsAt: nil, isActive: false),
                weekAllModels: UsageWindow(usedPercent: 20, resetsAt: nil, isActive: false),
                weekModels: [
                    ModelUsageWindow(
                        modelLabel: "Fable",
                        window: UsageWindow(
                            usedPercent: 60, resetsAt: nil, severity: .warning, isActive: true)
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
            codex: CodexUsageSnapshot(
                primary: nil, secondary: UsageWindow(usedPercent: 55, resetsAt: nil), planType: nil),
            fetchedAt: .now
        )
        #expect(primaryMissing.primaryUsedPercent(for: .codex) == 55)
    }

    @Test("Codex usage-based plans use consumed allowance percentage, not remaining percentage")
    func codexUsesAllowanceAfterRollingWindows() {
        let allowance = CodexSpendLimit(
            used: 21_987.778,
            limit: 60_000,
            remainingPercent: 63,
            resetsAt: .now
        )
        let snapshot = UsageSnapshot(
            claude: nil,
            codex: CodexUsageSnapshot(
                primary: nil,
                secondary: nil,
                planType: "business",
                individualLimit: allowance
            ),
            fetchedAt: .now
        )

        let percent = snapshot.primaryUsedPercent(for: .codex)
        #expect(percent != nil)
        #expect(abs((percent ?? 0) - 36.64629666666667) < 0.000_000_1)
        #expect(percent != allowance.remainingPercent)
        #expect(snapshot.primaryWindow(for: .codex, metric: .weekly)?.usedPercent == percent)
    }

    @Test("Allowance percentage is clamped and falls back to remaining percent when limit is zero")
    func codexAllowancePercentageFallback() {
        let noLimit = CodexSpendLimit(
            used: 10,
            limit: 0,
            remainingPercent: 120,
            resetsAt: .now
        )
        #expect(noLimit.remainingPercent == 100)
        #expect(noLimit.usedPercent == 0)

        let overLimit = CodexSpendLimit(
            used: 150,
            limit: 100,
            remainingPercent: -10,
            resetsAt: .now
        )
        #expect(overLimit.remainingPercent == 0)
        #expect(overLimit.usedPercent == 100)
    }

    @Test("Gemini CLI / Custom always return nil regardless of snapshot content")
    func geminiAndCustomAlwaysNil() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 90, resetsAt: nil), weekAllModels: nil),
            codex: CodexUsageSnapshot(
                primary: UsageWindow(usedPercent: 90, resetsAt: nil), secondary: nil, planType: nil),
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

    // MARK: - Limit selection by metric

    /// An explicitly configured limit beats both the highest-utilization and the
    /// is_active one: choosing "session only" is a deliberate statement that auto must
    /// not override.
    @Test("metric selects the requested window across agents")
    func metricSelectsRequestedWindow() {
        let snapshot = UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 12, resetsAt: nil, isActive: true),
                weekAllModels: UsageWindow(usedPercent: 40, resetsAt: nil),
                weekModels: [
                    ModelUsageWindow(modelLabel: "Opus", window: UsageWindow(usedPercent: 66, resetsAt: nil)),
                    ModelUsageWindow(
                        modelLabel: "Fable", window: UsageWindow(usedPercent: 88, resetsAt: nil)),
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
        // Per-model picks the highest limit, the one that hits its ceiling first.
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .weeklyModel)?.usedPercent == 88)
        // auto prefers is_active, so it picks session (12%).
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .auto)?.usedPercent == 12)

        // For Codex, session maps to primary and weekly to secondary.
        #expect(snapshot.primaryWindow(for: .codex, metric: .session)?.usedPercent == 20)
        #expect(snapshot.primaryWindow(for: .codex, metric: .weekly)?.usedPercent == 55)
    }

    /// Falls back to auto rather than hiding the gauge on an agent that has no such limit.
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

        // Claude has no session limit, so auto applies (weekAllModels 40%).
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .session)?.usedPercent == 40)
        // Claude has no per-model limit, so auto applies.
        #expect(snapshot.primaryWindow(for: .claudeCode, metric: .weeklyModel)?.usedPercent == 40)
        // Codex has no notion of a per-model limit, so auto applies (primary 20%).
        #expect(snapshot.primaryWindow(for: .codex, metric: .weeklyModel)?.usedPercent == 20)
        // Codex has no secondary limit, so auto applies (primary).
        #expect(snapshot.primaryWindow(for: .codex, metric: .weekly)?.usedPercent == 20)
        // An agent with no limits at all stays nil regardless of the metric.
        #expect(UsageSnapshot.empty.primaryWindow(for: .claudeCode, metric: .session) == nil)
        #expect(snapshot.primaryWindow(for: .geminiCLI, metric: .session) == nil)
    }
}
