import Foundation

/// Entry point that bundles Claude and Codex usage fetching.
/// The UI (`AgentNotch` target) reaches usage data only through this actor.
public actor UsageService {
    public static let shared = UsageService()

    private let fetchClaude: @Sendable () async -> ClaudeUsageFetch
    private let fetchCodex: @Sendable () async -> CodexUsageFetch
    private let now: @Sendable () -> Date

    public init(
        claudeClient: ClaudeUsageClient = .shared,
        codexClient: CodexUsageClient = .shared
    ) {
        fetchClaude = {
            await claudeClient.fetch()
        }
        fetchCodex = {
            await codexClient.fetch()
        }
        now = Date.init
    }

    init(
        fetchClaude: @escaping @Sendable () async -> ClaudeUsageFetch,
        fetchCodex: @escaping @Sendable () async -> CodexUsageFetch,
        now: @escaping @Sendable () -> Date
    ) {
        self.fetchClaude = fetchClaude
        self.fetchCodex = fetchCodex
        self.now = now
    }

    /// Fetches the latest snapshot for both Claude and Codex.
    /// If one cannot be fetched, the other is still returned, and the failure is carried as a
    /// reason rather than dropped — the gauge stays on screen either way and needs something to say.
    public func refresh() async -> UsageSnapshot {
        async let claudeFetch = fetchClaude()
        async let codexFetch = fetchCodex()
        let claude = await claudeFetch
        let codex = await codexFetch

        return UsageSnapshot(
            claude: snapshot(from: claude),
            codex: snapshot(from: codex),
            claudeUnavailable: reason(from: claude),
            codexUnavailable: reason(from: codex),
            fetchedAt: now()
        )
    }

    private func snapshot(from fetch: ClaudeUsageFetch) -> ClaudeUsageSnapshot? {
        guard case .success(let snapshot) = fetch else { return nil }
        return snapshot
    }

    private func snapshot(from fetch: CodexUsageFetch) -> CodexUsageSnapshot? {
        guard case .success(let snapshot) = fetch else { return nil }
        return snapshot
    }

    private func reason(from fetch: ClaudeUsageFetch) -> UsageUnavailableReason? {
        guard case .unavailable(let reason) = fetch else { return nil }
        return reason
    }

    private func reason(from fetch: CodexUsageFetch) -> UsageUnavailableReason? {
        guard case .unavailable(let reason) = fetch else { return nil }
        return reason
    }
}
