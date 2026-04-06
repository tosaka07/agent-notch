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

        func syncPanelState() {
            let expanded = viewModel.mode != .compact
            tracker.isExpanded = expanded
            self.panel?.ignoresMouseEvents = !expanded
        }
        syncPanelState()

        tracker.onNotchClicked = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            viewModel.toggle()
            syncPanelState()
        }

        tracker.onClickedOutside = { [weak viewModel] in
            guard let viewModel else { return }
            guard viewModel.mode != .compact else { return }
            viewModel.close()
            syncPanelState()
        }

        tracker.start()
        hotZoneTracker = tracker

        // Observe auto-expand notifications
        modeObservation = NotificationCenter.default.publisher(for: .agentNotchAutoExpand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] _ in
                guard let self, let viewModel else { return }
                _ = self  // retain for syncPanelState
                syncPanelState()
            }
    }
}
