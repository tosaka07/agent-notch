import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Guards the promise that the usage gauge is a permanent surface.
///
/// The bug these exist for: an expired Claude token produced a nil snapshot, the Claude gauge was
/// compacted out of the row, and the only remaining gauge was Codex's — so "Claude usage stopped
/// working" and "Claude usage was removed from the app" looked identical, with no surface left to
/// explain either.
@Suite("Usage gauge surface")
struct UsageGaugeSurfaceTests {
    private let claudeWindow = ClaudeUsageSnapshot(
        session: UsageWindow(usedPercent: 40, resetsAt: nil),
        weekAllModels: nil,
        weekModels: [],
        extraUsage: nil
    )
    private let codexWindow = CodexUsageSnapshot(
        primary: UsageWindow(usedPercent: 70, resetsAt: nil),
        secondary: nil,
        planType: nil,
        individualLimit: nil
    )

    private func items(
        _ snapshot: UsageSnapshot?,
        metric: UsageGaugeMetric = .auto,
        codexEnabled: Bool = true
    ) -> [UsageGaugeSurface.Item] {
        UsageGaugeSurface.items(
            snapshot: snapshot,
            metric: metric,
            codexIntegrationEnabled: codexEnabled
        )
    }

    @Test("Before the first poll both gauges exist and read as loading")
    func showsLoadingGaugesBeforeFirstPoll() {
        let result = items(nil)

        #expect(result.map(\.agentType) == [.claudeCode, .codex])
        #expect(result.allSatisfy { $0.percent == nil })
        // No reason yet: nothing has failed, the fetch is simply still in flight.
        #expect(result.allSatisfy { !$0.isUnavailable })
    }

    @Test("A failed Claude fetch keeps the Claude gauge, alongside a working Codex one")
    func keepsClaudeGaugeWhenOnlyCodexResolves() {
        let result = items(
            UsageSnapshot(
                claude: nil,
                codex: codexWindow,
                claudeUnavailable: .tokenExpired,
                fetchedAt: .now
            )
        )

        #expect(result.map(\.agentType) == [.claudeCode, .codex])
        #expect(result[0].reason == .tokenExpired)
        #expect(result[0].percent == nil)
        #expect(result[1].percent == 70)
        #expect(!result[1].isUnavailable)
    }

    @Test("Both gauges survive both fetches failing, each with its own reason")
    func keepsBothGaugesWhenEverythingFails() {
        let result = items(
            UsageSnapshot(
                claude: nil,
                codex: nil,
                claudeUnavailable: .notSignedIn,
                codexUnavailable: .agentUnreachable,
                fetchedAt: .now
            )
        )

        #expect(result.map(\.agentType) == [.claudeCode, .codex])
        #expect(result.map(\.reason) == [.notSignedIn, .agentUnreachable])
    }

    /// An unclassified miss still has to say something, and "no limit to report" is the only
    /// benign way to reach it — a window simply was not present in an otherwise fine response.
    @Test("A missing window with no recorded reason falls back to noLimits")
    func fallsBackToNoLimits() {
        let result = items(UsageSnapshot(claude: nil, codex: nil, fetchedAt: .now))

        #expect(result.allSatisfy { $0.reason == .noLimits })
    }

    /// The one legitimate way to lose a gauge: the user said they do not use Codex. That is a
    /// choice, not a failure, so there is nothing to explain and nothing to show.
    @Test("Turning the Codex integration off is the only thing that removes a gauge")
    func dropsCodexOnlyWhenIntegrationIsOff() {
        let snapshot = UsageSnapshot(claude: claudeWindow, codex: codexWindow, fetchedAt: .now)

        #expect(items(snapshot, codexEnabled: false).map(\.agentType) == [.claudeCode])
        #expect(items(nil, codexEnabled: false).map(\.agentType) == [.claudeCode])
        #expect(items(snapshot, codexEnabled: true).map(\.agentType) == [.claudeCode, .codex])
    }

    /// A metric that an agent does not have falls back to `auto` rather than blanking the gauge,
    /// so choosing a setting can never make a gauge read as unavailable.
    @Test("A metric the agent lacks falls back instead of reading as unavailable")
    func metricFallbackKeepsValue() {
        let result = items(
            UsageSnapshot(claude: claudeWindow, codex: codexWindow, fetchedAt: .now),
            metric: .weeklyModel
        )

        #expect(result[0].percent == 40)
        #expect(result[1].percent == 70)
        #expect(result.allSatisfy { !$0.isUnavailable })
    }

    @Test("Every reason has non-empty user-facing wording in both languages")
    func everyReasonHasWording() {
        for reason in UsageUnavailableReason.allCases {
            #expect(!reason.explanation.isEmpty)
            #expect(!reason.shortLabel.isEmpty)
        }
    }
}
