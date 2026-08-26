import AgentNotchCore
import AppKit
import Defaults
import SwiftUI

/// Manages notch panel placement and the display mode
/// (followFocus / mainDisplay / builtinOnly / specificDisplay / allDisplays).
///
/// - Repositions on screen configuration changes (`NSApplication.didChangeScreenParametersNotification`)
/// - In followFocus mode, follows the screen containing the pointer
/// - Observes `Defaults[.displayMode]` / `[.specificDisplayUUID]` and reapplies on change
@MainActor
final class DisplayCoordinator {
    private let sessionManager: SessionManager
    private let permissionActions: PermissionActions

    /// displayID → controller. A single entry except in allDisplays mode.
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

    /// Tears everything down and rebuilds it according to the current displayMode setting.
    private func applyDisplayMode() {
        focusedScreenTracker?.stop()
        focusedScreenTracker = nil
        for controller in windowControllers.values { controller.close() }
        windowControllers.removeAll()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        switch Defaults[.displayMode] {
        case .followFocus:
            let mouse = NSEvent.mouseLocation
            let screen =
                screens.first { $0.frame.contains(mouse) }
                ?? NSScreen.systemMain ?? screens[0]
            showNotch(on: screen)
            setupFocusedScreenTracker()

        case .mainDisplay:
            showNotch(on: NSScreen.systemMain ?? screens[0])

        case .builtinOnly:
            showNotch(on: NSScreen.builtin ?? NSScreen.systemMain ?? screens[0])

        case .specificDisplay:
            let targetUUID = Defaults[.specificDisplayUUID]
            let screen =
                screens.first { $0.displayUUID == targetUUID }
                ?? NSScreen.systemMain ?? screens[0]
            showNotch(on: screen)

        case .allDisplays:
            for screen in screens {
                showNotch(on: screen)
            }
        }
    }

    private func showNotch(on screen: NSScreen) {
        let id = screen.displayID
        if windowControllers[id] != nil { return }
        let controller = NotchWindowController(screen: screen)
        controller.keyboardInteraction.onWillEngage = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.disengageKeyboard(onEveryPanelExcept: controller)
        }
        let contentView = NotchRootView(
            sessionManager: sessionManager,
            notchSize: screen.notchSize,
            hasPhysicalNotch: screen.hasPhysicalNotch,
            permissionActions: permissionActions,
            keyboardInteraction: controller.keyboardInteraction
        )
        controller.show(contentView: contentView)
        windowControllers[id] = controller
    }

    private func disengageKeyboard(onEveryPanelExcept target: NotchWindowController) {
        for controller in windowControllers.values where controller !== target {
            controller.keyboardInteraction.disengage()
        }
    }

    /// Sends a global hot key to one panel only.
    ///
    /// In all-displays mode every panel renders the same pending permission.
    /// Broadcasting an approve/deny command would therefore submit it multiple
    /// times. Prefer an already-engaged panel, then the display under the mouse.
    func handleGlobalHotKey(_ action: GlobalHotKeyAction) {
        keyboardTargetController()?.keyboardInteraction.handleGlobal(action)
    }

    private func keyboardTargetController() -> NotchWindowController? {
        if let engaged = windowControllers.values.first(where: {
            $0.keyboardInteraction.isEngaged
        }) {
            return engaged
        }

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
            let controller = windowControllers[screen.displayID]
        {
            return controller
        }

        for screen in NSScreen.screens {
            if let controller = windowControllers[screen.displayID] {
                return controller
            }
        }
        return windowControllers.values.first
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
            // Follow the pointer's screen only while in followFocus mode.
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
