import AgentNotchCore
import AppKit

enum HotZoneClickTarget: Equatable {
    case notch
    case content
    case outside
    case ignored
}

enum HotZoneClickResolver {
    static func target(
        at location: CGPoint,
        notchRect: CGRect,
        contentRect: CGRect?,
        isExpanded: Bool
    ) -> HotZoneClickTarget {
        if notchRect.contains(location) { return .notch }
        guard isExpanded else { return .ignored }
        if let contentRect, contentRect.contains(location) { return .content }
        return .outside
    }
}

/// Handles click detection for the notch area.
/// - Global monitor: detects notch clicks (compact mode, panel is canBecomeKey=false).
/// - Local monitor: detects notch toggle clicks and outside-content clicks (expanded mode).
///
/// Hover is handled by SwiftUI .onHover — no AppKit mouse move monitors needed.
@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedInside: (() -> Void)?
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
        switch HotZoneClickResolver.target(
            at: location,
            notchRect: geometry.notchScreenRect,
            contentRect: contentScreenRect?(),
            isExpanded: isExpanded
        ) {
        case .notch:
            Log.input.debug("Global: notchClicked")
            onNotchClicked?()
        case .content:
            // A nonactivating panel can receive its first click while another
            // app remains active. Treat that as engagement, not dismissal.
            Log.input.debug("Global: clickedInside")
            onClickedInside?()
        case .outside:
            Log.input.debug("Global: clickedOutside")
            onClickedOutside?()
        case .ignored:
            break
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
            // Another notch panel (all-displays mode) or the settings window
            // may own this click. Closing this panel must not swallow the event
            // before its real target receives it.
            return false
        }

        // Inside content — let SwiftUI handle
        onClickedInside?()
        return false
    }
}
