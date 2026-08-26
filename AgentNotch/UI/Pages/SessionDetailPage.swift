import AgentNotchCore
import SwiftUI

/// Thin wrapper for the `sessionDetail(id)` mode. Shows SessionDetailView if the
/// session exists, otherwise falls back to ExpandedPage.
struct SessionDetailPage: View {
    let sessionId: String
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager
    /// Needed to present `ExpandedPageView` as the fallback when no session is
    /// found. `SessionDetailView` itself no longer shows usage, so it does not
    /// reference this.
    @ObservedObject var usageCoordinator: UsageCoordinator
    let keyboardInteraction: KeyboardInteractionController

    var body: some View {
        if let session = sessionManager.session(for: sessionId) {
            SessionDetailView(
                session: session,
                sessionManager: sessionManager,
                physicalNotchHeight: viewModel.physicalNotchHeight,
                onBack: { viewModel.backToList() },
                onClose: { viewModel.close() },
                onShowSession: { id in viewModel.showSession(id) },
                keyboardInteraction: keyboardInteraction
            )
            // State the panel's real size so the content is always held to this
            // width. The shell's (NotchShell's) frame is only a proposal, so an
            // element with an intrinsic width — a glyph, or text that does not
            // wrap — could otherwise spill out sideways.
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .clipped()
        } else {
            ExpandedPageView(
                viewModel: viewModel,
                sessionManager: sessionManager,
                usageCoordinator: usageCoordinator,
                keyboardInteraction: keyboardInteraction
            )
        }
    }
}
