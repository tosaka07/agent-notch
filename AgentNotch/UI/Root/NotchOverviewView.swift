import AgentNotchCore
import SwiftUI

/// Retains the lightweight compact chrome while the overview opens and closes.
///
/// The shell owns surface geometry. This view owns content identity and derives
/// every presentation value from one expansion progress, so content never
/// participates in the shell's per-frame width layout.
struct NotchOverviewView: View {
    let viewModel: NotchViewModel
    let notificationManager: NotchNotificationManager
    let focusController: NotificationFocusController
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var usageCoordinator: UsageCoordinator
    let keyboardInteraction: KeyboardInteractionController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expansion: CGFloat

    init(
        viewModel: NotchViewModel,
        notificationManager: NotchNotificationManager,
        focusController: NotificationFocusController,
        sessionManager: SessionManager,
        usageCoordinator: UsageCoordinator,
        keyboardInteraction: KeyboardInteractionController
    ) {
        self.viewModel = viewModel
        self.notificationManager = notificationManager
        self.focusController = focusController
        self.sessionManager = sessionManager
        self.usageCoordinator = usageCoordinator
        self.keyboardInteraction = keyboardInteraction
        self._expansion = State(
            initialValue: NotchOverviewTarget(mode: viewModel.mode)?.expansion ?? 0
        )
    }

    private var target: NotchOverviewTarget {
        NotchOverviewTarget(mode: viewModel.mode) ?? .compact
    }

    var body: some View {
        let motion = NotchOverviewMotion(expansion: expansion)

        ZStack(alignment: .top) {
            // This view stays mounted for compact, notification, and expanded.
            // Its left and right wings therefore keep their SwiftUI identity
            // instead of being recreated on each mode change.
            CompactPageView(
                viewModel: viewModel,
                notificationManager: notificationManager,
                focusController: focusController,
                sessionManager: sessionManager,
                motion: motion
            )

            // The session list is mounted at its final dimensions. Only the
            // container's presentation values animate, so text and cards never
            // reflow at intermediate shell widths.
            if target == .expanded {
                ExpandedPageView(
                    viewModel: viewModel,
                    sessionManager: sessionManager,
                    usageCoordinator: usageCoordinator,
                    keyboardInteraction: keyboardInteraction
                )
                .frame(
                    width: NotchPresentationLayout.expandedSize.width,
                    height: NotchPresentationLayout.expandedSize.height,
                    alignment: .top
                )
                .offset(y: motion.expandedOffsetY)
                .opacity(motion.expandedOpacity)
            }
        }
        .frame(
            width: viewModel.notchWidth,
            height: viewModel.notchHeight,
            alignment: .top
        )
        // Mode changes arrive inside other animation transactions. Yielding
        // gives overview content its own cancellable transaction; a rapid
        // reversal cancels this task and animates the same scalar back.
        .task(id: target) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(
                NotchPresentationAnimation.animation(
                    expanding: target == .expanded,
                    reduceMotion: reduceMotion
                )
            ) {
                expansion = target.expansion
            }
        }
    }
}
