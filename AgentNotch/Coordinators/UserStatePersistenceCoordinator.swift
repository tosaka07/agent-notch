import AgentNotchCore
import Defaults
import Foundation

/// Bridge that persists `SessionManager.userStates` into `Defaults[.sessionUserStates]`.
///
/// - Restores from Defaults at launch
/// - Subscribes to `onUserStateChange` and writes changes back, debounced
/// - `stop()` synchronously flushes anything unsaved for a clean shutdown
@MainActor
final class UserStatePersistenceCoordinator {
    private let sessionManager: SessionManager
    private let debounceInterval: TimeInterval
    private var pendingSave: DispatchWorkItem?

    init(sessionManager: SessionManager, debounceInterval: TimeInterval = 0.3) {
        self.sessionManager = sessionManager
        self.debounceInterval = debounceInterval
    }

    func start() {
        let stored = Defaults[.sessionUserStates]
        if !stored.isEmpty {
            sessionManager.restoreUserStates(stored)
        }
        sessionManager.onUserStateChange = { [weak self] in
            self?.scheduleSave()
        }
    }

    /// Shutdown. Writes any unsaved state out to Defaults in one go.
    func stop() {
        pendingSave?.cancel()
        pendingSave = nil
        flushNow()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func flushNow() {
        Defaults[.sessionUserStates] = sessionManager.userStates
        pendingSave = nil
    }
}
