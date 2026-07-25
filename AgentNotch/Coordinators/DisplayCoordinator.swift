import AgentNotchCore
import AppKit
import Defaults
import SwiftUI

/// Notch パネルの配置と表示モード（followFocus / allDisplays / builtinOnly / specificDisplay）を管理する。
///
/// - 画面の接続変更 (`NSApplication.didChangeScreenParametersNotification`) を検知して再配置
/// - followFocus モードではフォーカスされたスクリーンに追従
/// - `Defaults[.displayMode]` / `[.specificDisplayUUID]` の変更を監視して再適用
@MainActor
final class DisplayCoordinator {
    private let sessionManager: SessionManager
    private let permissionActions: PermissionActions

    /// displayID → controller. followFocus/builtinOnly/specificDisplay は単一、allDisplays は複数エントリ。
    private var windowControllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var screenObserver: ScreenObserver?
    private var focusedScreenTracker: FocusedScreenTracker?
    private var displayModeObservations: [Any] = []

    init(sessionManager: SessionManager, permissionActions: PermissionActions) {
        self.sessionManager = sessionManager
        self.permissionActions = permissionActions
    }

    func start() {
        applyDisplayMode()
        setupScreenObserver()
        observeDisplayModeSetting()
    }

    func stop() {
        focusedScreenTracker?.stop()
        focusedScreenTracker = nil
        for controller in windowControllers.values { controller.close() }
        windowControllers.removeAll()
        screenObserver = nil
        displayModeObservations.removeAll()
    }

    // MARK: - Display mode

    /// 現在の displayMode 設定に従って全てを teardown → 再構築する。
    private func applyDisplayMode() {
        focusedScreenTracker?.stop()
        focusedScreenTracker = nil
        for controller in windowControllers.values { controller.close() }
        windowControllers.removeAll()

        switch Defaults[.displayMode] {
        case .followFocus:
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
                ?? NSScreen.builtin ?? NSScreen.screens[0]
            showNotch(on: screen)
            setupFocusedScreenTracker()

        case .allDisplays:
            for screen in NSScreen.screens {
                showNotch(on: screen)
            }

        case .builtinOnly:
            if let builtin = NSScreen.builtin {
                showNotch(on: builtin)
            } else {
                showNotch(on: NSScreen.screens[0])
            }

        case .specificDisplay:
            let targetUUID = Defaults[.specificDisplayUUID]
            let screen = NSScreen.screens.first { $0.displayUUID == targetUUID }
                ?? NSScreen.builtin ?? NSScreen.screens[0]
            showNotch(on: screen)
        }
    }

    private func showNotch(on screen: NSScreen) {
        let id = screen.displayID
        if windowControllers[id] != nil { return }
        let controller = NotchWindowController(screen: screen)
        let contentView = NotchRootView(
            sessionManager: sessionManager,
            notchSize: screen.notchSize,
            hasPhysicalNotch: screen.hasPhysicalNotch,
            permissionActions: permissionActions
        )
        controller.show(contentView: contentView)
        windowControllers[id] = controller
    }

    // MARK: - Observers

    private func setupScreenObserver() {
        let observer = ScreenObserver()
        observer.onScreenChanged = { [weak self] in
            self?.applyDisplayMode()
        }
        screenObserver = observer
    }

    private func setupFocusedScreenTracker() {
        let tracker = FocusedScreenTracker()
        tracker.onScreenChanged = { [weak self] screen in
            guard let self else { return }
            // followFocus モード中のみ、フォーカスされたスクリーンに追従
            guard Defaults[.displayMode] == .followFocus else { return }
            let newID = screen.displayID
            for (id, controller) in self.windowControllers where id != newID {
                controller.close()
                self.windowControllers.removeValue(forKey: id)
            }
            self.showNotch(on: screen)
        }
        tracker.start()
        focusedScreenTracker = tracker
    }

    private func observeDisplayModeSetting() {
        let handler: (Any) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.applyDisplayMode()
            }
        }
        displayModeObservations = [
            Defaults.observe(.displayMode) { handler($0) },
            Defaults.observe(.specificDisplayUUID) { handler($0) },
        ]
    }
}
