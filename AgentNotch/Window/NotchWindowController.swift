import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var hostingView: PassThroughHostingView<NotchContentView>?
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

    func show(contentView: NotchContentView) {
        // Fixed large window — covers the area the notch content can expand into.
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.maxY - windowHeight,
            width: screen.frame.width,
            height: windowHeight
        )

        let panel = NotchPanel(contentRect: windowFrame)
        let hosting = PassThroughHostingView(rootView: contentView)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hosting

        self.viewModelRef = contentView.viewModel
        setupHitTestRect(viewModel: contentView.viewModel, hosting: hosting)
        setupHotZoneTracker(viewModel: contentView.viewModel)
    }

    func close() {
        hotZoneTracker?.stop()
        hotZoneTracker = nil
        modeObservations.forEach { $0.cancel() }
        modeObservations.removeAll()
        panel?.close()
        panel = nil
        hostingView = nil
    }

    private func setupHitTestRect(viewModel: NotchViewModel, hosting: PassThroughHostingView<NotchContentView>) {
        hosting.hitTestRect = { [weak self] in
            guard let self else { return .zero }
            let screenFrame = self.screen.frame
            let w = viewModel.notchWidth
            let h = viewModel.notchHeight
            let screenX = screenFrame.midX - w / 2
            let screenY = screenFrame.maxY - h
            // Convert to hosting view's local coordinates
            let windowFrame = self.panel?.frame ?? screenFrame
            return CGRect(x: screenX - windowFrame.origin.x,
                          y: screenY - windowFrame.origin.y,
                          width: w, height: h)
        }
    }

    private func setupHotZoneTracker(viewModel: NotchViewModel) {
        let tracker = HotZoneTracker(geometry: geometry)

        // Content rect in screen coordinates — shared between hitTest and HotZoneTracker
        let screenFrame = self.geometry.screenFrame
        func currentContentScreenRect() -> CGRect {
            let w = viewModel.notchWidth
            let h = viewModel.notchHeight
            return CGRect(
                x: screenFrame.midX - w / 2,
                y: screenFrame.maxY - h,
                width: w, height: h
            )
        }

        tracker.contentScreenRect = { currentContentScreenRect() }

        func syncPanelState() {
            let expanded = viewModel.mode.isFullPanel
            let isNotif = viewModel.mode == .notification
            let interactive = expanded || isNotif
            tracker.isExpanded = expanded
            tracker.isNotification = isNotif
            if interactive {
                self.panel?.ignoresMouseEvents = false
                self.panel?.makeKey()
            } else {
                // Delay ignoresMouseEvents until close animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard viewModel.mode == .compact else { return }
                    self.panel?.ignoresMouseEvents = true
                }
            }
        }
        syncPanelState()

        tracker.onNotchClicked = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            viewModel.isHovering = false
            viewModel.toggle()
            syncPanelState()
        }

        tracker.onClickedOutside = { [weak viewModel] in
            guard let viewModel else { return }
            guard viewModel.mode != .compact else { return }
            viewModel.isHovering = false
            viewModel.close()
            syncPanelState()
        }

        tracker.onNotchHoverChanged = { [weak viewModel] hovering in
            guard let viewModel else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.isHovering = hovering
            }
        }

        tracker.start()
        hotZoneTracker = tracker

        // Observe notifications that change mode and need panel state sync
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
                    // Delay slightly to let SwiftUI update mode first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        syncPanelState()
                    }
                }
        }
    }
}
