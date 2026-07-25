import AgentNotchCore
import SwiftUI

/// `sessionDetail(id)` モード用の薄い wrapper。
/// セッションが存在すれば SessionDetailView を表示、無ければ ExpandedPage にフォールバック。
struct SessionDetailPage: View {
    let sessionId: String
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager
    /// フォールバック（セッションが見つからない場合）で `ExpandedPageView` を表示するために必要。
    /// `SessionDetailView` 自体はもう使用量表示を持たないため参照しない。
    @ObservedObject var usageCoordinator: UsageCoordinator

    var body: some View {
        if let session = sessionManager.session(for: sessionId) {
            SessionDetailView(
                session: session,
                sessionManager: sessionManager,
                onBack: { viewModel.backToList() },
                onShowSession: { id in viewModel.showSession(id) }
            )
            // パネルの実寸を明示して中身を必ずこの幅に収める。
            // 外殻（NotchShell）の frame は「提案」なので、中で固有幅を持つ要素
            // （グリフや折り返さないテキスト）が現れると横にはみ出せてしまう。
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .clipped()
        } else {
            ExpandedPageView(
                viewModel: viewModel,
                sessionManager: sessionManager,
                usageCoordinator: usageCoordinator
            )
        }
    }
}
