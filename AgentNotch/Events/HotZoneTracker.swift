import AgentNotchCore
import AppKit

/// Handles click detection for the notch area.
/// - Global monitor: detects notch clicks (compact) and outside clicks (expanded, other apps).
/// - Local monitor: detects notch clicks and outside-content clicks when panel is active.
@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?
    var onNotchHoverChanged: ((Bool) -> Void)?
    var onNotificationClicked: (() -> Void)?

    var isExpanded = false
    var isNotification = false
    private var wasHovering = false

    /// Returns the current visible content rect in screen coordinates.
    /// Set by NotchWindowController; used to detect clicks on transparent panel area.
    var contentScreenRect: (() -> CGRect)?

    private let eventMonitor = MouseEventMonitor()
    private var moveMonitor: Any?

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
        // Global mouse move for hover detection
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHover()
            }
        }
    }

    func stop() {
        eventMonitor.stopMonitoring()
        if let moveMonitor {
            NSEvent.removeMonitor(moveMonitor)
            self.moveMonitor = nil
        }
    }

    /// Check if point is in the visible notch content area (wings included).
    private func isPointInNotchContent(_ point: CGPoint) -> Bool {
        if let rect = contentScreenRect?() {
            return rect.contains(point)
        }
        return geometry.isPointInNotch(point)
    }

    private func updateHover() {
        guard !isExpanded else {
            if wasHovering { wasHovering = false; onNotchHoverChanged?(false) }
            return
        }
        let location = NSEvent.mouseLocation
        let hovering = isPointInNotchContent(location)
        if hovering != wasHovering {
            wasHovering = hovering
            Log.input.debug("Hover changed: \(hovering)")
            onNotchHoverChanged?(hovering)
        }
    }

    // MARK: - Global (clicks outside our app)

    private func handleGlobal(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        if isNotification {
            // Panel is ignoresMouseEvents=true, so we handle clicks via global monitor
            if let rect = contentScreenRect?(), rect.contains(location) {
                Log.input.debug("Global: notificationClicked at \(location.debugDescription)")
                onNotificationClicked?()
            }
            return
        }
        // When compact: use full content rect (wings). When expanded: use physical notch only.
        let isNotchClick = isExpanded
            ? geometry.isPointInNotch(location)
            : isPointInNotchContent(location)
        if isNotchClick {
            Log.input.debug("Global: notchClicked at \(location.debugDescription)")
            onNotchClicked?()
        } else if isExpanded {
            Log.input.debug("Global: clickedOutside at \(location.debugDescription)")
            onClickedOutside?()
        }
    }

    // MARK: - Local (clicks on our panel window)

    private func handleLocal(_ event: NSEvent) -> Bool {
        let location = NSEvent.mouseLocation

        if isNotification {
            if let rect = contentScreenRect?(), rect.contains(location) {
                Log.input.debug("Local: notificationClicked at \(location.debugDescription)")
                onNotificationClicked?()
                return true
            }
            return false
        }

        let isNotchClick = isExpanded
            ? geometry.notchScreenRect.contains(location)
            : isPointInNotchContent(location)
        if isNotchClick {
            Log.input.debug("Local: notchClicked at \(location.debugDescription)")
            onNotchClicked?()
            return true
        }

        guard isExpanded else { return false }

        // Click on the panel's transparent area (outside visible content) → close
        if let rect = contentScreenRect?(), !rect.contains(location) {
            Log.input.debug("Local: clickedOutside at \(location.debugDescription)")
            onClickedOutside?()
            return true
        }

        // Inside visible content — let SwiftUI handle it
        return false
    }
}
