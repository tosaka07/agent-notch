import AgentNotchCore
import Foundation

/// 日毎の推定コストを定期的に集計し `@Published report` を更新する。
///
/// `UsageCoordinator`（現在の使用率スナップショット）とは性質が違うので分けている:
/// こちらはネットワークを使わず、代わりにローカルログ（数百 MB）を走査する重い I/O。
/// 全走査でも 1 秒未満だが、使用率と同じ 180 秒間隔で回す必要はないので interval は長め。
///
/// 取得は `Task.detached` で off-MainActor 実行し、結果だけ MainActor に戻す
/// （`UsageCoordinator` と同じ流儀）。
@MainActor
final class DailyCostCoordinator: ObservableObject {
    /// Claude Code の日毎コスト。
    @Published private(set) var claude: DailyCostReport?
    /// Codex の日毎コスト。
    @Published private(set) var codex: DailyCostReport?

    private var timer: Timer?
    private let interval: TimeInterval
    private var isRefreshing = false
    private var lastComputedAt: Date = .distantPast

    init(interval: TimeInterval = 600) {
        self.interval = interval
    }

    func start() {
        stop()
        refreshIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfNeeded()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 直近の集計から `interval` 未満、または集計中であればスキップする。
    private func refreshIfNeeded() {
        guard !isRefreshing else { return }
        guard Date().timeIntervalSince(lastComputedAt) >= interval else { return }

        isRefreshing = true
        Task.detached(priority: .utility) { [weak self] in
            let claudeReport = DailyCostAggregator.claudeReport()
            let codexReport = DailyCostAggregator.codexReport()
            await MainActor.run {
                self?.claude = claudeReport
                self?.codex = codexReport
                self?.lastComputedAt = Date()
                self?.isRefreshing = false
            }
        }
    }
}
