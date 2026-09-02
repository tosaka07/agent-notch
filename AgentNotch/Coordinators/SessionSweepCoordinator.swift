import AgentNotchCore
import Defaults
import Foundation

/// Runs every 30 seconds to settle held-back `Stop`s
/// (`SessionManager.resolveDeferredStops()`), then reconcile process presence and remove
/// sessions whose configured retention expired or whose working directory disappeared
/// (`SessionManager.sweepStale(...)`). Posts `.agentNotchSessionSwept` only for cards
/// actually removed; a settled deferral is a state change, not a removal, and is only logged.
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
        // Settling a held-back Stop comes first: it can move a card to .idle, which is what
        // makes the retention timeout below able to reach it at all.
        let settled = sessionManager.resolveDeferredStops()
        for id in settled {
            Log.events.info("Stop deferral settled (idle) id=\(id)")
        }

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
