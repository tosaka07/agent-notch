import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Daily cost refresh policy", .serialized)
@MainActor
struct DailyCostCoordinatorTests {
    @Test("Opening the usage page reuses a fresh in-memory report")
    func openingPageReusesFreshReport() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let source = ReportSource()
        let coordinator = DailyCostCoordinator(
            interval: 600,
            now: { clock.now },
            fetchReports: { source.fetch() }
        )

        coordinator.start()
        try await waitForRefresh(coordinator)
        coordinator.stop()

        clock.advance(by: 599)
        coordinator.start()
        try await waitForRefresh(coordinator)
        coordinator.stop()

        #expect(source.fetchCount == 1)
        #expect(coordinator.claude == source.claude)
        #expect(coordinator.codex == source.codex)
    }

    @Test("Keeping the usage page open does not rescan local logs")
    func openPageDoesNotStartPeriodicRescans() async throws {
        let source = ReportSource()
        let coordinator = DailyCostCoordinator(
            interval: 0.03,
            fetchReports: { source.fetch() }
        )

        coordinator.start()
        try await waitForRefresh(coordinator)
        try await Task.sleep(for: .milliseconds(100))
        coordinator.stop()

        #expect(source.fetchCount == 1)
    }

    @Test("The reload button bypasses the daily-cost cache")
    func manualReloadBypassesCache() async throws {
        let source = ReportSource()
        let coordinator = DailyCostCoordinator(
            interval: 600,
            fetchReports: { source.fetch() }
        )

        coordinator.start()
        try await waitForRefresh(coordinator)
        coordinator.forceRefresh()
        try await waitForRefresh(coordinator)

        #expect(source.fetchCount == 2)
    }

    private func waitForRefresh(
        _ coordinator: DailyCostCoordinator
    ) async throws {
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

    private final class ReportSource: @unchecked Sendable {
        private let lock = NSLock()
        private var storedFetchCount = 0

        let claude = DailyCostReport(
            days: [DailyCost(day: Date(timeIntervalSince1970: 100), estimatedCostUSD: 1.25)],
            unsupportedModels: [],
            computedAt: Date(timeIntervalSince1970: 1_000)
        )
        let codex = DailyCostReport(
            days: [DailyCost(day: Date(timeIntervalSince1970: 100), estimatedCostUSD: 2.5)],
            unsupportedModels: [],
            computedAt: Date(timeIntervalSince1970: 1_000)
        )

        var fetchCount: Int {
            lock.withLock { storedFetchCount }
        }

        func fetch() -> (claude: DailyCostReport, codex: DailyCostReport) {
            lock.withLock {
                storedFetchCount += 1
            }
            return (claude, codex)
        }
    }
}
