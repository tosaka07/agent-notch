import AgentNotchCore
import AppKit

/// Handles click detection for the notch area.
/// - Global monitor: detects notch clicks (compact mode, panel is canBecomeKey=false).
/// - Local monitor: detects notch toggle clicks and outside-content clicks (expanded mode).
///
/// Hover is handled by SwiftUI .onHover — no AppKit mouse move monitors needed.
@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?

    var isExpanded = false

    /// Current visible content rect in screen coordinates.
    var contentScreenRect: (() -> CGRect)?

    private let eventMonitor = MouseEventMonitor()

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func start() {
        eventMonitor.startMonitoring(
            mask: .leftMouseDown,
            globalHandler: { [weak self] event in self?.handleGlobal(event) },
            localHandler: { [weak self] event in self?.handleLocal(event) ?? false }
        )
    }

    func stop() {
        eventMonitor.stopMonitoring()
    }

    // MARK: - Global (clicks when another app is focused)

    private func handleGlobal(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        if geometry.isPointInNotch(location) {
            Log.input.debug("Global: notchClicked")
            onNotchClicked?()
        } else if isExpanded {
            Log.input.debug("Global: clickedOutside")
            onClickedOutside?()
        }
    }

    // MARK: - Local (clicks on our panel)

    private func handleLocal(_ event: NSEvent) -> Bool {
        let location = NSEvent.mouseLocation

        // Physical notch area → toggle
        if geometry.notchScreenRect.contains(location) {
            Log.input.debug("Local: notchClicked")
            onNotchClicked?()
            return true
        }

        // Non-expanded: let SwiftUI handle (buttons, notification rows, etc.)
        guard isExpanded else { return false }

        // Expanded: click outside content → close
        if let rect = contentScreenRect?(), !rect.contains(location) {
            Log.input.debug("Local: clickedOutside")
            onClickedOutside?()
            return true
        }

        // Inside content — let SwiftUI handle
        return false
    }
}
