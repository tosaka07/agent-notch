import AgentNotchCore
import SwiftUI

/// Notch パネルのルート View。
/// - state 保持: `NotchViewModel`（navigation）, `NotchNotificationManager`（通知キュー）,
///   `CompletionGlowController`（glow 演出）, `NotificationFocusController`（キーボードフォーカス）
/// - mode に応じた Page を表示し、外殻は `NotchShell`、副作用は `NotchEventRouter` に委譲。
struct NotchRootView: View {
    @State var viewModel: NotchViewModel
    @State private var notificationManager = NotchNotificationManager()
    @State private var glow = CompletionGlowController()
    @State private var focusController = NotificationFocusController()
    @ObservedObject var sessionManager: SessionManager
    private let permissionActions: PermissionActions

    init(
        sessionManager: SessionManager,
        notchSize: CGSize = CGSize(width: 224, height: 38),
        initialMode: NotchMode = .compact,
        permissionActions: PermissionActions = PermissionActions()
    ) {
        self._viewModel = State(initialValue: NotchViewModel(notchSize: notchSize, initialMode: initialMode))
        self.sessionManager = sessionManager
        self.permissionActions = permissionActions
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.mode {
            case .compact, .notification:
                CompactPageView(
                    viewModel: viewModel,
                    notificationManager: notificationManager,
                    focusController: focusController,
                    sessionManager: sessionManager
                )
            case .expanded:
                ExpandedPageView(viewModel: viewModel, sessionManager: sessionManager)
            case .sessionDetail(let sessionId):
                SessionDetailPage(
                    sessionId: sessionId,
                    viewModel: viewModel,
                    sessionManager: sessionManager
                )
            }
        }
        .notchShell(viewModel: viewModel, glow: glow)
        .notchEventRouter(
            viewModel: viewModel,
            notificationManager: notificationManager,
            glow: glow,
            focusController: focusController,
            sessionManager: sessionManager
        )
        .environment(\.permissionActions, permissionActions)
    }
}
