import AppKit

@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    /// Current panel size (updated by NotchWindowController when mode changes)
    var currentPanelWidth: CGFloat = 0
    var currentPanelHeight: CGFloat = 0

    private let eventMonitor = MouseEventMonitor()
    private var isHovering = false

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .mouseMoved]
        eventMonitor.startMonitoring(
            globalMask: mask,
            localMask: mask,
            handler: { [weak self] event in
                self?.handleEvent(event)
            }
        )
    }

    func stop() {
        eventMonitor.stopMonitoring()
    }

    private func handleEvent(_ event: NSEvent) {
        let location = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            if geometry.isPointInNotch(location) {
                onNotchClicked?()
            } else if isInsidePanel(location) {
                // Click inside the expanded panel — let SwiftUI handle it
                // Do nothing
            } else {
                onClickedOutside?()
            }

        case .mouseMoved:
            let inNotch = geometry.isPointInNotch(location)
            let inPanel = isInsidePanel(location)
            let hovering = inNotch || inPanel
            if hovering != isHovering {
                isHovering = hovering
                onHoverChanged?(hovering)
            }

        default:
            break
        }
    }

    private func isInsidePanel(_ point: CGPoint) -> Bool {
        guard currentPanelWidth > 0, currentPanelHeight > 0 else { return false }
        return geometry.isPointInWindow(
            point,
            isExpanded: true,
            expandedWidth: currentPanelWidth,
            expandedHeight: currentPanelHeight
        )
    }
}
