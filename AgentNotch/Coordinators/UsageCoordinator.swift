import AgentNotchCore
import Foundation

/// Claude / Codex の使用量を定期的に取得し `@Published snapshot` を更新する。
///
/// Claude 側は undocumented API（`ClaudeUsageClient` 参照）を叩くため、
/// aggressive rate limit を避けて interval を長め（デフォルト 180 秒）に取る。
/// 取得は `Task.detached` で off-MainActor 実行し、結果だけ MainActor に戻す。
@MainActor
final class UsageCoordinator: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?

    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = 180) {
        self.interval = interval
    }

    func start() {
        stop()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        Task.detached(priority: .utility) {
            let result = await UsageService.shared.refresh()
            await MainActor.run { [weak self] in
                self?.snapshot = result
            }
        }
    }
}
