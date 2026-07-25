import AgentNotchCore
import SwiftUI

/// `sessionDetail(id)` モード用の薄い wrapper。
/// セッションが存在すれば SessionDetailView を表示、無ければ ExpandedPage にフォールバック。
struct SessionDetailPage: View {
    let sessionId: String
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var usageCoordinator: UsageCoordinator

    var body: some View {
        if let session = sessionManager.session(for: sessionId) {
            SessionDetailView(
                session: session,
                sessionManager: sessionManager,
                usageCoordinator: usageCoordinator,
                onBack: { viewModel.backToList() },
                onShowSession: { id in viewModel.showSession(id) }
            )
        } else {
            ExpandedPageView(viewModel: viewModel, sessionManager: sessionManager)
        }
    }
}
