import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var hotZoneTracker: HotZoneTracker?
    let geometry: NotchGeometry
    let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        self.geometry = NotchGeometry(
            notchSize: screen.notchSize,
            screenFrame: screen.frame
        )
    }

    func show(contentView: NotchContentView) {
        // Use the full expanded frame so content has room to expand into
        let frame = geometry.windowFrame(
            expandedWidth: 650,
            expandedHeight: 500,
            isExpanded: true
        )
        let panel = NotchPanel(contentRect: frame)
        panel.contentView = NSHostingView(rootView: contentView)
        panel.orderFrontRegardless()
        self.panel = panel

        setupHotZoneTracker(viewModel: contentView.viewModel)
    }

    func close() {
        hotZoneTracker?.stop()
        hotZoneTracker = nil
        panel?.close()
        panel = nil
    }

    private func setupHotZoneTracker(viewModel: NotchViewModel) {
        let tracker = HotZoneTracker(geometry: geometry)

        tracker.onNotchClicked = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            viewModel.toggle()
            // When expanded, allow mouse events so the panel is interactive
            self.panel?.ignoresMouseEvents = viewModel.mode == .compact
        }

        tracker.onClickedOutside = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            guard viewModel.mode != .compact else { return }
            viewModel.close()
            self.panel?.ignoresMouseEvents = true
        }

        tracker.onHoverChanged = { _ in
            // Reserved for future hover effects
        }

        tracker.start()
        hotZoneTracker = tracker
    }
}
