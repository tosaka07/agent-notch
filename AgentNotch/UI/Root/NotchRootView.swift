import AgentNotchCore
import Defaults
import SwiftUI

/// Root view of the notch panel.
/// - Owns the state: `NotchViewModel` (navigation), `NotchNotificationManager`
///   (notification queue), `CompletionGlowController` (glow effect),
///   `NotificationFocusController` (keyboard focus).
/// - Renders the page for the current mode; the shell is delegated to
///   `NotchShell` and the side effects to `NotchEventRouter`.
///
/// A single `UsageCoordinator` is held here and passed down to
/// `ExpandedPageView` (the `UsageGauge` on the left of the session list's top
/// bar). Creating it inside the page would reset the 180-second refetch guard
/// on every mode transition (see `UsageCoordinator`).
struct NotchRootView: View {
    @State var viewModel: NotchViewModel
    @State private var notificationManager = NotchNotificationManager()
    @State private var glow = CompletionGlowController()
    @State private var focusController = NotificationFocusController()
    @State private var usageCoordinator = UsageCoordinator()
    /// Daily cost scans local logs (no network, heavy I/O), so it gets its own
    /// coordinator separate from the usage rate.
    @State private var dailyCostCoordinator = DailyCostCoordinator()
    @ObservedObject var sessionManager: SessionManager
    private let permissionActions: PermissionActions
    let keyboardInteraction: KeyboardInteractionController
    @Default(.usageEnabled) private var usageEnabled

    init(
        sessionManager: SessionManager,
        notchSize: CGSize = CGSize(width: 224, height: 38),
        hasPhysicalNotch: Bool = true,
        initialMode: NotchMode = .compact,
        permissionActions: PermissionActions = PermissionActions(),
        keyboardInteraction: KeyboardInteractionController = KeyboardInteractionController()
    ) {
        self._viewModel = State(
            initialValue: NotchViewModel(
                notchSize: notchSize,
                initialMode: initialMode,
                hasPhysicalNotch: hasPhysicalNotch
            ))
        self.sessionManager = sessionManager
        self.permissionActions = permissionActions
        self.keyboardInteraction = keyboardInteraction
    }

    var body: some View {
        VStack(spacing: 0) {
            if NotchOverviewTarget(mode: viewModel.mode) != nil {
                NotchOverviewView(
                    viewModel: viewModel,
                    notificationManager: notificationManager,
                    focusController: focusController,
                    sessionManager: sessionManager,
                    usageCoordinator: usageCoordinator,
                    keyboardInteraction: keyboardInteraction
                )
            } else {
                switch viewModel.mode {
                case .sessionDetail(let sessionId):
                    SessionDetailPage(
                        sessionId: sessionId,
                        viewModel: viewModel,
                        sessionManager: sessionManager,
                        usageCoordinator: usageCoordinator,
                        keyboardInteraction: keyboardInteraction
                    )
                case .usage:
                    UsagePageView(
                        viewModel: viewModel,
                        usageCoordinator: usageCoordinator,
                        dailyCostCoordinator: dailyCostCoordinator,
                        keyboardInteraction: keyboardInteraction
                    )
                case .compact, .notification, .expanded:
                    EmptyView()
                }
            }
        }
        // Keep detail and usage page replacement immediate. Overview content
        // owns a separate, cancellable animation transaction after this mode
        // transaction completes.
        //
        // Mode changes can arrive inside `withAnimation` from the event router.
        // Letting that transaction reach the page switch cross-fades heavy page
        // identities and can retain an outgoing ScrollView.
        .transaction(value: viewModel.mode) { $0.animation = nil }
        .notchShell(viewModel: viewModel, glow: glow)
        .notchEventRouter(
            viewModel: viewModel,
            notificationManager: notificationManager,
            glow: glow,
            focusController: focusController,
            sessionManager: sessionManager,
            keyboardInteraction: keyboardInteraction
        )
        .environment(\.permissionActions, permissionActions)
        .environment(\.locale, AppLocalization.language.locale)
        .onAppear {
            syncUsageCoordinator(for: viewModel.mode)
            keyboardInteraction.updateContext(interactionContext)
        }
        .onChange(of: viewModel.mode) { _, mode in
            syncUsageCoordinator(for: mode)
        }
        .onChange(of: interactionContext) { _, context in
            keyboardInteraction.updateContext(context)
        }
        .onChange(of: usageEnabled) { _, enabled in
            if enabled {
                // Turning it on explicitly signals "you may try again".
                Task { await ClaudeCredentialsProvider.shared.reset() }
                syncUsageCoordinator(for: viewModel.mode)
            } else {
                usageCoordinator.stop()
            }
        }
    }

    private var interactionContext: KeyboardInteractionContext {
        switch viewModel.mode {
        case .compact:
            return .compact
        case .notification:
            return .notification
        case .expanded:
            return .expanded
        case .sessionDetail(let sessionId):
            guard let session = sessionManager.session(for: sessionId) else {
                return .sessionDetail
            }
            switch session.currentInterruption {
            case .permission: return .permission
            case .question: return .question
            case nil: return .sessionDetail
            }
        case .usage:
            return .usage
        }
    }

    /// Usage is shown by `ExpandedPageView` (the gauge on the left of the
    /// session list's top bar) and `UsagePageView` (the usage detail page), so
    /// polling only runs while one of them is visible. While `usageEnabled` is
    /// off, nothing touches Claude's credentials or the undocumented API.
    private func syncUsageCoordinator(for mode: NotchMode) {
        guard usageEnabled else {
            usageCoordinator.stop()
            dailyCostCoordinator.stop()
            return
        }
        switch mode {
        case .expanded, .usage:
            usageCoordinator.start()
        case .compact, .notification, .sessionDetail:
            usageCoordinator.stop()
        }
        // Daily cost is aggregated only while the usage page is open — the I/O
        // is heavy, so it never runs behind the session list.
        if case .usage = mode {
            dailyCostCoordinator.start()
        } else {
            dailyCostCoordinator.stop()
        }
    }
}
