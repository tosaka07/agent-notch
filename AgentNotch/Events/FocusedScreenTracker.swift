import AppKit

/// Tracks which screen should show the notch overlay.
/// Uses mouse position (works with tiling WMs like Aerospace) + app activation as fallback.
@MainActor
final class FocusedScreenTracker {
    var onScreenChanged: ((NSScreen) -> Void)?

    private var currentDisplayID: CGDirectDisplayID = 0
    private var appObservation: Any?
    private var mouseMonitor: Any?
    private var debounceTask: Task<Void, Never>?

    func start() {
        currentDisplayID = screenForMouse()?.displayID ?? 0

        // 1. App activation — catches most normal switching
        appObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkScreenChange()
            }
        }

        // 2. Global mouse-moved — catches Aerospace / tiling WM focus changes
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.debouncedCheckScreenChange()
            }
        }
    }

    func stop() {
        if let appObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(appObservation)
        }
        appObservation = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Debounce mouse-moved checks (fire at most once per 150ms)
    private func debouncedCheckScreenChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            checkScreenChange()
        }
    }

    private func checkScreenChange() {
        guard let screen = screenForMouse() else { return }
        guard screen.displayID != currentDisplayID else { return }
        currentDisplayID = screen.displayID
        onScreenChanged?(screen)
    }

    private func screenForMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}
