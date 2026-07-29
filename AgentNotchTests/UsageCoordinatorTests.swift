import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Usage refresh policy", .serialized)
@MainActor
struct UsageCoordinatorTests {
    @Test("Reopening expanded view reuses a fresh usage snapshot")
    func reopeningExpandedViewReusesSnapshot() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000))
        let source = UsageSource(
            snapshot: UsageSnapshot(
                claude: ClaudeUsageSnapshot(
                    session: UsageWindow(usedPercent: 25, resetsAt: nil),
                    weekAllModels: nil
                ),
                codex: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        let coordinator = UsageCoordinator(
            interval: 180,
            now: { clock.now },
            fetchUsage: { await source.fetch() }
        )

        coordinator.start()
        try await waitForRefresh(coordinator)
        coordinator.stop()

        clock.advance(by: 179)
        coordinator.start()
        try await waitForRefresh(coordinator)
        coordinator.stop()

        #expect(await source.fetchCount == 1)
        let expectedSnapshot = source.snapshot
        #expect(coordinator.snapshot == expectedSnapshot)
    }

    @Test("Keeping expanded view open refreshes usage after its interval")
    func expandedViewPeriodicallyRefreshesUsage() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 3_000))
        let source = UsageSource(
            snapshot: UsageSnapshot(
                claude: nil,
                codex: nil,
                fetchedAt: Date(timeIntervalSince1970: 3_000)
            )
        )
        let scheduler = ManualUsageRefreshScheduler()
        let coordinator = UsageCoordinator(
            interval: 180,
            now: { clock.now },
            scheduler: scheduler,
            fetchUsage: { await source.fetch() }
        )

        coordinator.start()
        try await waitForRefresh(coordinator)
        clock.advance(by: 181)
        scheduler.fire()
        try await waitForRefresh(coordinator)
        coordinator.stop()

        #expect(await source.fetchCount == 2)
    }

    private func waitForRefresh(_ coordinator: UsageCoordinator) async throws {
        for _ in 0..<200 where coordinator.isRefreshing {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(coordinator.isRefreshing == false)
    }

    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date

        init(_ value: Date) {
            self.value = value
        }

        var now: Date {
            lock.withLock { value }
        }

        func advance(by interval: TimeInterval) {
            lock.withLock {
                value = value.addingTimeInterval(interval)
            }
        }
    }

    private actor UsageSource {
        let snapshot: UsageSnapshot
        private(set) var fetchCount = 0

        init(snapshot: UsageSnapshot) {
            self.snapshot = snapshot
        }

        func fetch() -> UsageSnapshot {
            fetchCount += 1
            return snapshot
        }
    }

    @MainActor
    private final class ManualUsageRefreshScheduler: UsageRefreshScheduling {
        private var action: (@MainActor () -> Void)?

        func schedule(
            every _: TimeInterval,
            action: @escaping @MainActor () -> Void
        ) {
            self.action = action
        }

        func cancel() {
            action = nil
        }

        func fire() {
            action?()
        }
    }
}
