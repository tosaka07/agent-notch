import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    let geometry: NotchGeometry
    let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        self.geometry = NotchGeometry(
            notchSize: screen.notchSize,
            screenFrame: screen.frame
        )
    }

    func show(rootView: some View) {
        let frame = geometry.windowFrame(
            expandedWidth: 650,
            expandedHeight: 500,
            isExpanded: false
        )
        let panel = NotchPanel(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
