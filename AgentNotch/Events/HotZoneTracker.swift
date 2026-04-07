import AppKit

/// Handles click detection for the notch area.
/// - Global monitor: detects notch clicks (compact) and outside clicks (expanded, other apps).
/// - Local monitor: detects notch clicks and outside-content clicks when panel is active.
@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?

    var isExpanded = false

    /// Returns the current visible content rect in screen coordinates.
    /// Set by NotchWindowController; used to detect clicks on transparent panel area.
    var contentScreenRect: (() -> CGRect)?

    private let eventMonitor = MouseEventMonitor()

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func start() {
        eventMonitor.startMonitoring(
            mask: .leftMouseDown,
            globalHandler: { [weak self] event in
                self?.handleGlobal(event)
            },
            localHandler: { [weak self] event in
                self?.handleLocal(event) ?? false
            }
        )
    }

    func stop() {
        eventMonitor.stopMonitoring()
    }

    // MARK: - Global (clicks outside our app)

    private func handleGlobal(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        if geometry.isPointInNotch(location) {
            onNotchClicked?()
        } else if isExpanded {
            onClickedOutside?()
        }
    }

    // MARK: - Local (clicks on our panel window)

    private func handleLocal(_ event: NSEvent) -> Bool {
        let location = NSEvent.mouseLocation

        if geometry.notchScreenRect.contains(location) {
            onNotchClicked?()
            return true
        }

        guard isExpanded else { return false }

        // Click on the panel's transparent area (outside visible content) → close
        if let rect = contentScreenRect?(), !rect.contains(location) {
            onClickedOutside?()
            return true
        }

        // Inside visible content — let SwiftUI handle it
        return false
    }
}
