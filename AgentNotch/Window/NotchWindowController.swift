import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var hotZoneTracker: HotZoneTracker?
    private var modeObservation: AnyCancellable?
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
        let frame = geometry.windowFrame(
            expandedWidth: 650,
            expandedHeight: 550,
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
        modeObservation?.cancel()
        modeObservation = nil
        panel?.close()
        panel = nil
    }

    private func setupHotZoneTracker(viewModel: NotchViewModel) {
        let tracker = HotZoneTracker(geometry: geometry)

        // Update panel size based on current mode
        func updateTrackerSize() {
            tracker.currentPanelWidth = viewModel.notchWidth
            tracker.currentPanelHeight = viewModel.notchHeight
        }
        updateTrackerSize()

        tracker.onNotchClicked = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            viewModel.toggle()
            self.panel?.ignoresMouseEvents = viewModel.mode == .compact
            updateTrackerSize()
        }

        tracker.onClickedOutside = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            guard viewModel.mode != .compact else { return }
            viewModel.close()
            self.panel?.ignoresMouseEvents = true
            updateTrackerSize()
        }

        tracker.onHoverChanged = { _ in }

        tracker.start()
        hotZoneTracker = tracker

        // Observe mode changes from auto-expand (notifications) to update tracker + panel
        modeObservation = NotificationCenter.default.publisher(for: .agentNotchAutoExpand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] _ in
                guard let self, let viewModel else { return }
                self.panel?.ignoresMouseEvents = viewModel.mode == .compact
                updateTrackerSize()
            }
    }
}
