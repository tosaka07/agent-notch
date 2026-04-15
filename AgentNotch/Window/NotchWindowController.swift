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

    var currentMode: NotchMode { viewModelRef?.mode ?? .compact }

    init(screen: NSScreen) {
        self.screen = screen
        self.geometry = NotchGeometry(
            notchSize: screen.notchSize,
            screenFrame: screen.frame
        )
    }

    // MARK: - Window sizing (boring.notch pattern)
    // Window is fixed at max content size. SwiftUI animates inside it.
    // No setFrame after creation — only setFrameOrigin for positioning.

    /// Max content dimensions + shadow padding
    private static let maxContentWidth: CGFloat = 640
    private static let maxContentHeight: CGFloat = 520
    private static let shadowPadding: CGFloat = 40  // for CompletionFlare bleed

    /// Width: padding on both sides. Height: padding on bottom only (top is flush with screen edge).
    private var windowSize: CGSize {
        CGSize(
            width: Self.maxContentWidth + Self.shadowPadding * 2,
            height: Self.maxContentHeight + Self.shadowPadding
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

        self.panel = panel
        self.viewModelRef = contentView.viewModel
        setupHotZoneTracker(viewModel: contentView.viewModel)
    }

    func close() {
        hotZoneTracker?.stop()
        hotZoneTracker = nil
        modeObservations.forEach { $0.cancel() }
        modeObservations.removeAll()
        panel?.close()
        panel = nil
    }

    // MARK: - HotZoneTracker

    private func setupHotZoneTracker(viewModel: NotchViewModel) {
        let tracker = HotZoneTracker(geometry: geometry)

        let screenFrame = self.geometry.screenFrame
        tracker.contentScreenRect = {
            let w = viewModel.notchWidth
            let h = viewModel.notchHeight
            return CGRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
        }

        func syncState() {
            Log.panel.debug("syncState mode=\(String(describing: viewModel.mode))")
            tracker.isExpanded = viewModel.mode.isFullPanel
        }
        syncState()

        tracker.onNotchClicked = { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.isHovering = false
            viewModel.toggle()
            syncState()
        }

        tracker.onClickedOutside = { [weak viewModel] in
            guard let viewModel, viewModel.mode != .compact else { return }
            viewModel.isHovering = false
            viewModel.close()
            syncState()
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

        // Key focus toggle for keyboard navigation
        modeObservations.append(
            NotificationCenter.default.publisher(for: .agentNotchSetKeyFocus)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, let enable = notification.object as? Bool else { return }
                    self.panel?.allowKeyFocus = enable
                    if enable {
                        self.panel?.makeKey()
                    } else {
                        self.panel?.resignKey()
                    }
                }
        )
    }
}
