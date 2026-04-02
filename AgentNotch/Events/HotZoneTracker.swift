import AppKit

@MainActor
final class HotZoneTracker {
    let geometry: NotchGeometry

    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

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
            } else {
                onClickedOutside?()
            }

        case .mouseMoved:
            let inNotch = geometry.isPointInNotch(location)
            if inNotch != isHovering {
                isHovering = inNotch
                onHoverChanged?(inNotch)
            }

        default:
            break
        }
    }
}
