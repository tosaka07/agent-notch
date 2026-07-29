import AgentNotchCore
import Foundation

/// Aggregates estimated daily cost when the usage page opens or the user reloads it.
///
/// Kept separate from `UsageCoordinator` (the current usage-rate snapshot) because the
/// work is different in kind: no network here, but heavy I/O scanning local logs
/// (hundreds of MB). Results stay cached in memory, and opening the page only
/// recomputes them after the cache interval. No timer runs while the page remains open.
///
/// Aggregation runs off-MainActor via `Task.detached`; only the result is handed back
/// to the MainActor (same approach as `UsageCoordinator`).
@MainActor
final class DailyCostCoordinator: ObservableObject {
    /// Daily cost for Claude Code.
    @Published private(set) var claude: DailyCostReport?
    /// Daily cost for Codex.
    @Published private(set) var codex: DailyCostReport?
    /// Whether an aggregation is in flight. Drives the manual reload button's spinner/disabled state.
    @Published private(set) var isRefreshing = false

    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private let fetchReports:
        @Sendable () -> (
            claude: DailyCostReport,
            codex: DailyCostReport
        )
    private var lastComputedAt: Date = .distantPast

    init(
        interval: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init,
        fetchReports:
            @escaping @Sendable () -> (
                claude: DailyCostReport,
                codex: DailyCostReport
            ) = {
                (
                    DailyCostAggregator.claudeReport(),
                    DailyCostAggregator.codexReport()
                )
            }
    ) {
        self.interval = interval
        self.now = now
        self.fetchReports = fetchReports
    }

    func start() {
        refreshIfNeeded()
    }

    func stop() {}

    /// Page-open refresh: skips if less than `interval` has passed since the last
    /// aggregation. `forceRefresh()` separately powers the explicit reload button.
    private func refreshIfNeeded() {
        guard now().timeIntervalSince(lastComputedAt) >= interval else { return }
        forceRefresh()
    }

    /// Recomputes immediately, ignoring the interval (for the reload button).
    /// Does nothing while an aggregation is already running.
    func forceRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let fetchReports = fetchReports
        let now = now
        Task.detached(priority: .utility) { [weak self] in
            let reports = fetchReports()
            await MainActor.run {
                self?.claude = reports.claude
                self?.codex = reports.codex
                self?.lastComputedAt = now()
                self?.isRefreshing = false
            }
        }
    }
}
