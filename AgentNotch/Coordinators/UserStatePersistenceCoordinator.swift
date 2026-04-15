import AgentNotchCore
import Defaults
import Foundation

/// `SessionManager.userStates` を `Defaults[.sessionUserStates]` に永続化するブリッジ。
///
/// - 起動時に Defaults から復元
/// - `onUserStateChange` を購読し、変更を debounce 付きで書き戻す
/// - `stop()` で未保存分を同期フラッシュして安全に終了
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

    /// 終了処理。未保存分をまとめて Defaults に書き出す。
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
