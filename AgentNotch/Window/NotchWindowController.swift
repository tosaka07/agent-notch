import AgentNotchCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var hotZoneTracker: HotZoneTracker?
    private var modeObservations: [AnyCancellable] = []
    private weak var viewModelRef: NotchViewModel?
    let geometry: NotchGeometry
    let screen: NSScreen
    let keyboardInteraction = KeyboardInteractionController()

    init(screen: NSScreen) {
        self.screen = screen
        self.geometry = NotchGeometry(
            notchSize: screen.notchSize,
            screenFrame: screen.frame
        )
    }

    // MARK: - Window sizing
    // Window is fixed at max content size. SwiftUI animates inside it.
    // No setFrame after creation — only setFrameOrigin for positioning.

    private static let shadowPadding: CGFloat = 40  // for CompletionFlare bleed

    /// Width: padding on both sides. Height: padding on bottom only (top is flush with screen edge).
    private var windowSize: CGSize {
        CGSize(
            width: NotchPresentationLayout.stageSize.width + Self.shadowPadding * 2,
            height: NotchPresentationLayout.stageSize.height + Self.shadowPadding
        )
    }

    func show(contentView: NotchRootView) {
        let size = windowSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let panel = NotchPanel(contentRect: frame)
        let hosting = NotchHostingView(rootView: contentView)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        keyboardInteraction.attach(to: panel)

        self.panel = panel
        self.viewModelRef = contentView.viewModel
        setupHotZoneTracker(viewModel: contentView.viewModel)
    }

    func close() {
        hotZoneTracker?.stop()
        hotZoneTracker = nil
        for observation in modeObservations { observation.cancel() }
        modeObservations.removeAll()
        keyboardInteraction.detach()
        panel?.close()
        panel = nil
    }

    // MARK: - HotZoneTracker

    private func setupHotZoneTracker(viewModel: NotchViewModel) {
        let tracker = HotZoneTracker(geometry: geometry)

        let screenFrame = self.geometry.screenFrame
        tracker.contentScreenRect = {
            let w = viewModel.notchWidth
            // Include the completion pill that hangs below, outside the panel; otherwise
            // a tap on it is swallowed as an outside click and closes the panel.
            let h = viewModel.notchHeight + viewModel.bottomAccessoryHeight
            return CGRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
        }

        func syncState() {
            Log.panel.debug("syncState mode=\(String(describing: viewModel.mode))")
            tracker.isExpanded = viewModel.mode.isFullPanel
        }
        syncState()

        tracker.onNotchClicked = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            viewModel.isHovering = false
            viewModel.toggle()
            if viewModel.mode.isFullPanel {
                self.keyboardInteraction.engage()
            } else {
                self.keyboardInteraction.disengage()
            }
            syncState()
        }

        tracker.onClickedOutside = { [weak self, weak viewModel] in
            guard let self, let viewModel, viewModel.mode != .compact else { return }
            viewModel.isHovering = false
            viewModel.close()
            self.keyboardInteraction.disengage()
            syncState()
        }

        tracker.onClickedInside = { [weak self] in
            self?.keyboardInteraction.engage()
        }

        tracker.start()
        hotZoneTracker = tracker

        let notifications: [Notification.Name] = [
            .agentNotchAutoExpand,
            .agentNotchSessionCompleted,
            .agentNotchSessionResumed,
            .agentNotchClosePanel,
        ]
        modeObservations = notifications.map { name in
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard self != nil else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        syncState()
                    }
                }
        }

    }
}
