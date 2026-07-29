import AgentNotchCore
import Defaults
import Foundation

/// Calls `SessionManager.sweepStale(...)` every 30 seconds to reconcile process presence and
/// remove sessions whose configured retention expired or whose working directory disappeared.
/// Posts `.agentNotchSessionSwept` only for cards actually removed.
@MainActor
final class SessionSweepCoordinator {
    private let sessionManager: SessionManager
    private var timer: Timer?
    private let interval: TimeInterval
    private let timeoutSeconds: () -> Int
    private let notificationCenter: NotificationCenter

    init(
        sessionManager: SessionManager,
        interval: TimeInterval = 30,
        timeoutSeconds: @escaping () -> Int = {
            Defaults[.sessionTimeout].rawValue
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.sessionManager = sessionManager
        self.interval = interval
        self.timeoutSeconds = timeoutSeconds
        self.notificationCenter = notificationCenter
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
        let timeout = timeoutSeconds()
        let swept = sessionManager.sweepStale(timeoutSeconds: timeout)
        for item in swept {
            let reason: String =
                switch item.reason {
                case .directoryDeleted: L("Directory deleted")
                case .timeout: L("Timed out")
                case .processDead: L("Process ended")
                }
            notificationCenter.post(
                name: .agentNotchSessionSwept,
                object: item.id,
                userInfo: [
                    "projectName": item.projectName,
                    "message": L("Removed \(item.projectName) automatically (\(reason))"),
                ]
            )
        }
    }
}
