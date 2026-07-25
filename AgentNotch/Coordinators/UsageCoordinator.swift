import AgentNotchCore
import Foundation

/// Claude / Codex の使用量を定期的に取得し `@Published snapshot` を更新する。
///
/// Claude 側は undocumented API（`ClaudeUsageClient` 参照）を叩くため、
/// aggressive rate limit を避けて interval を長め（デフォルト 180 秒）に取る。
/// 取得は `Task.detached` で off-MainActor 実行し、結果だけ MainActor に戻す。
///
/// Expanded 表示のたびに `start()` が呼ばれる（onAppear/onDisappear 駆動）ため、
/// 短時間の開閉を繰り返しても interval 未満では再取得しないようガードする。
@MainActor
final class UsageCoordinator: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?

    private var timer: Timer?
    private let interval: TimeInterval
    private var isRefreshing = false

    init(interval: TimeInterval = 180) {
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

    /// 直近の取得から `interval` 未満、または取得中であればスキップする。
    private func refreshIfNeeded() {
        guard !isRefreshing else { return }
        let elapsed = Date().timeIntervalSince(snapshot?.fetchedAt ?? .distantPast)
        guard elapsed >= interval else { return }

        isRefreshing = true
        Task.detached(priority: .utility) { [weak self] in
            let result = await UsageService.shared.refresh()
            await MainActor.run {
                self?.snapshot = result
                self?.isRefreshing = false
            }
        }
    }
}
