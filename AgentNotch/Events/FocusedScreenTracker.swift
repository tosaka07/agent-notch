import AppKit

/// Tracks which screen has the focused app and fires a callback when it changes.
/// Uses NSWorkspace app activation notifications — no Accessibility permission required.
@MainActor
final class FocusedScreenTracker {
    var onScreenChanged: ((NSScreen) -> Void)?

    private var currentDisplayID: CGDirectDisplayID = 0
    private var observation: Any?

    func start() {
        currentDisplayID = effectiveScreen()?.displayID ?? 0

        observation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkScreenChange()
            }
        }
    }

    func stop() {
        if let observation {
            NSWorkspace.shared.notificationCenter.removeObserver(observation)
        }
        observation = nil
    }

    private func checkScreenChange() {
        // Ignore our own app being activated (e.g., status menu click)
        if NSWorkspace.shared.frontmostApplication == NSRunningApplication.current { return }

        guard let screen = effectiveScreen() else { return }
        guard screen.displayID != currentDisplayID else { return }
        currentDisplayID = screen.displayID
        onScreenChanged?(screen)
    }

    /// The screen of the currently focused app.
    /// NSScreen.main returns the screen containing the key window's menu bar.
    private func effectiveScreen() -> NSScreen? {
        if let main = NSScreen.main { return main }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}
