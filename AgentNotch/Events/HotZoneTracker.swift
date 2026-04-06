import AppKit

/// Handles click detection for the notch area.
/// - Compact mode: global monitor detects notch clicks to open the panel.
/// - Expanded mode: global monitor detects outside clicks to close the panel.
///   The NSPanel handles all clicks inside the expanded panel natively (SwiftUI).
@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?

    /// Set by NotchWindowController when mode changes.
    var isExpanded = false

    private let eventMonitor = MouseEventMonitor()

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func start() {
        eventMonitor.startMonitoring(mask: .leftMouseDown) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    func stop() {
        eventMonitor.stopMonitoring()
    }

    private func handleEvent(_ event: NSEvent) {
        let location = NSEvent.mouseLocation

        if geometry.isPointInNotch(location) {
            onNotchClicked?()
        } else if isExpanded {
            // Clicked outside the notch while expanded → close
            onClickedOutside?()
        }
        // Compact + outside notch → ignore (nothing to close)
    }
}
