import AgentNotchCore
import Defaults
import Foundation

/// 30 秒ごとに `SessionManager.sweepStale(...)` を呼び、古くなった/
/// 作業ディレクトリが消えたセッションを削除し、UI への通知（`.agentNotchSessionSwept`）を発火する。
@MainActor
final class SessionSweepCoordinator {
    private let sessionManager: SessionManager
    private var timer: Timer?
    private let interval: TimeInterval

    init(sessionManager: SessionManager, interval: TimeInterval = 30) {
        self.sessionManager = sessionManager
        self.interval = interval
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sweep()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sweep() {
        let timeout = Defaults[.sessionTimeout].rawValue
        let swept = sessionManager.sweepStale(timeoutSeconds: timeout)
        for item in swept {
            let reason: String = switch item.reason {
            case .directoryDeleted: "ディレクトリ削除"
            case .timeout: "タイムアウト"
            case .processDead: "プロセス終了"
            }
            NotificationCenter.default.post(
                name: .agentNotchSessionSwept,
                object: item.id,
                userInfo: [
                    "projectName": item.projectName,
                    "message": "\(item.projectName) を自動削除しました（\(reason)）",
                ]
            )
        }
    }
}
