import AgentNotchCore
import Foundation

@MainActor
protocol UsageRefreshScheduling: AnyObject {
    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    )
    func cancel()
}

@MainActor
private final class TimerUsageRefreshScheduler: UsageRefreshScheduling {
    private var timer: Timer?

    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                action()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

/// Periodically fetches Claude / Codex usage and updates `@Published snapshot`.
///
/// The Claude side hits an undocumented API (see `ClaudeUsageClient`), so the
/// interval is kept long (180 seconds by default) to stay clear of aggressive
/// rate limits. Fetching runs off-MainActor via `Task.detached`; only the result
/// is handed back to the MainActor.
///
/// `start()` is called every time the expanded view appears (driven by
/// onAppear/onDisappear), so repeated open/close within the interval must not
/// trigger a refetch.
@MainActor
final class UsageCoordinator: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    /// Whether a fetch is in flight. Drives the manual reload button's spinner/disabled state.
    @Published private(set) var isRefreshing = false

    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private let scheduler: any UsageRefreshScheduling
    private let fetchUsage: @Sendable () async -> UsageSnapshot

    init(
        interval: TimeInterval = 180,
        now: @escaping @Sendable () -> Date = Date.init,
        scheduler: any UsageRefreshScheduling = TimerUsageRefreshScheduler(),
        fetchUsage: @escaping @Sendable () async -> UsageSnapshot = {
            await UsageService.shared.refresh()
        }
    ) {
        self.interval = interval
        self.now = now
        self.scheduler = scheduler
        self.fetchUsage = fetchUsage
    }

    func start() {
        stop()
        refreshIfNeeded()
        scheduler.schedule(every: interval) { [weak self] in
            self?.refreshIfNeeded()
        }
    }

    func stop() {
        scheduler.cancel()
    }

    /// Timer-driven refresh: skips if less than `interval` has passed since the last
    /// fetch, or if a fetch is already running.
    private func refreshIfNeeded() {
        let elapsed = now().timeIntervalSince(snapshot?.fetchedAt ?? .distantPast)
        guard elapsed >= interval else { return }
        forceRefresh()
    }

    /// Refetches immediately, ignoring the interval (for the reload button).
    /// Does nothing while a fetch is already running.
    func forceRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let fetchUsage = fetchUsage
        Task.detached(priority: .utility) { [weak self] in
            let result = await fetchUsage()
            await MainActor.run {
                self?.snapshot = result
                self?.isRefreshing = false
            }
        }
    }
}
