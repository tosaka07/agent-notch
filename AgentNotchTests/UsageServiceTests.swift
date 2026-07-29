import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Usage service aggregation")
struct UsageServiceTests {
    @Test("Public composition delegates to both usage clients")
    func publicComposition() async {
        let credentials = ClaudeCredentialsProvider(loader: { nil })
        let claudeClient = ClaudeUsageClient(credentials: credentials)
        let codex = CodexUsageSnapshot(
            primary: nil,
            secondary: nil,
            planType: "business",
            individualLimit: CodexSpendLimit(
                used: 25,
                limit: 100,
                remainingPercent: 75,
                resetsAt: .now
            )
        )
        let codexClient = CodexUsageClient(
            fetchFromAppServer: { codex },
            fetchFromRollout: { nil }
        )
        let service = UsageService(
            claudeClient: claudeClient,
            codexClient: codexClient
        )

        let snapshot = await service.refresh()

        #expect(snapshot.claude == nil)
        #expect(snapshot.codex == codex)
    }

    @Test("Refresh combines both usage providers with the fetch timestamp")
    func combinesProviders() async {
        let claude = ClaudeUsageSnapshot(
            session: UsageWindow(usedPercent: 20, resetsAt: nil),
            weekAllModels: nil
        )
        let codex = CodexUsageSnapshot(
            primary: UsageWindow(usedPercent: 40, resetsAt: nil),
            secondary: nil,
            planType: "plus"
        )
        let date = Date(timeIntervalSince1970: 1_234)
        let service = UsageService(
            fetchClaude: { .success(claude) },
            fetchCodex: { .success(codex) },
            now: { date }
        )

        let snapshot = await service.refresh()

        #expect(snapshot == UsageSnapshot(claude: claude, codex: codex, fetchedAt: date))
    }

    @Test("One unavailable provider does not hide the other")
    func partialSnapshot() async {
        let codex = CodexUsageSnapshot(
            primary: nil,
            secondary: UsageWindow(usedPercent: 60, resetsAt: nil),
            planType: "pro"
        )
        let date = Date(timeIntervalSince1970: 5_678)
        let service = UsageService(
            fetchClaude: { .unavailable(.tokenExpired) },
            fetchCodex: { .success(codex) },
            now: { date }
        )

        let snapshot = await service.refresh()

        #expect(snapshot.claude == nil)
        #expect(snapshot.codex == codex)
        #expect(snapshot.fetchedAt == date)
    }

    /// The reason has to survive aggregation, since this is the only path by which the gauge's
    /// empty state learns what to say.
    @Test("Each provider's unavailable reason reaches the snapshot independently")
    func carriesReasonsPerProvider() async {
        let service = UsageService(
            fetchClaude: { .unavailable(.tokenExpired) },
            fetchCodex: { .unavailable(.integrationDisabled) },
            now: { Date(timeIntervalSince1970: 1) }
        )

        let snapshot = await service.refresh()

        #expect(snapshot.unavailableReason(for: .claudeCode) == .tokenExpired)
        #expect(snapshot.unavailableReason(for: .codex) == .integrationDisabled)
    }

    /// A successful fetch must not leave a stale reason behind, or the UI would show a value and
    /// an excuse for it at the same time.
    @Test("A successful fetch reports no reason")
    func successCarriesNoReason() async {
        let claude = ClaudeUsageSnapshot(
            session: UsageWindow(usedPercent: 20, resetsAt: nil),
            weekAllModels: nil
        )
        let service = UsageService(
            fetchClaude: { .success(claude) },
            fetchCodex: { .unavailable(.notSignedIn) },
            now: { Date(timeIntervalSince1970: 1) }
        )

        let snapshot = await service.refresh()

        #expect(snapshot.unavailableReason(for: .claudeCode) == nil)
        #expect(snapshot.unavailableReason(for: .codex) == .notSignedIn)
        // Agents with no usage concept never report a reason.
        #expect(snapshot.unavailableReason(for: .geminiCLI) == nil)
    }
}
