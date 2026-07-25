import AgentNotchCore
import Defaults
import SwiftUI

/// Notch パネルのルート View。
/// - state 保持: `NotchViewModel`（navigation）, `NotchNotificationManager`（通知キュー）,
///   `CompletionGlowController`（glow 演出）, `NotificationFocusController`（キーボードフォーカス）
/// - mode に応じた Page を表示し、外殻は `NotchShell`、副作用は `NotchEventRouter` に委譲。
///
/// `UsageCoordinator` はここで一つだけ保持し、`expanded` / `sessionDetail` の
/// 両方に同じインスタンスを渡す。Page 側でそれぞれ生成すると 180 秒の
/// 再取得ガードがモード遷移のたびにリセットされてしまうため（`UsageCoordinator` 参照）。
struct NotchRootView: View {
    @State var viewModel: NotchViewModel
    @State private var notificationManager = NotchNotificationManager()
    @State private var glow = CompletionGlowController()
    @State private var focusController = NotificationFocusController()
    @State private var usageCoordinator = UsageCoordinator()
    @ObservedObject var sessionManager: SessionManager
    private let permissionActions: PermissionActions
    @Default(.usageEnabled) private var usageEnabled

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
                    sessionManager: sessionManager,
                    usageCoordinator: usageCoordinator
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
        .onAppear { syncUsageCoordinator(for: viewModel.mode) }
        .onChange(of: viewModel.mode) { _, mode in
            syncUsageCoordinator(for: mode)
        }
        .onChange(of: usageEnabled) { _, enabled in
            if enabled {
                // 明示的な ON は「もう一度試してよい」という意思表示（#38）。
                Task { await ClaudeCredentialsProvider.shared.reset() }
                syncUsageCoordinator(for: viewModel.mode)
            } else {
                usageCoordinator.stop()
            }
        }
    }

    /// 使用量取得が必要な画面（`expanded` / `sessionDetail`）が見えている間だけポーリングする。
    /// `usageEnabled` が OFF の間は、Claude の資格情報にも undocumented API にも一切触らない（#38）。
    private func syncUsageCoordinator(for mode: NotchMode) {
        guard usageEnabled else {
            usageCoordinator.stop()
            return
        }
        switch mode {
        case .expanded, .sessionDetail:
            usageCoordinator.start()
        case .compact, .notification:
            usageCoordinator.stop()
        }
    }
}
