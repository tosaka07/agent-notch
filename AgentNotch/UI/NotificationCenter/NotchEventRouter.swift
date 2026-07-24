import AgentNotchCore
import Defaults
import SwiftUI

/// `agentNotch*` 系の NotificationCenter メッセージと state の onChange を一箇所で dispatch する ViewModifier。
/// ここに集めることで、root view からは副作用の一覧性が確保される。
struct NotchEventRouter: ViewModifier {
    let viewModel: NotchViewModel
    let notificationManager: NotchNotificationManager
    let glow: CompletionGlowController
    let focusController: NotificationFocusController
    @ObservedObject var sessionManager: SessionManager

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    func body(content: Content) -> some View {
        let hasSessions = !sessionManager.activeSessions.isEmpty

        content
            .onAppear { viewModel.hasActivity = hasSessions }
            .onChange(of: hasSessions) { _, newValue in
                viewModel.hasActivity = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchAutoExpand)) { notification in
                if let sessionId = notification.object as? String {
                    withAnimation(openAnimation) {
                        viewModel.showSession(sessionId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchSessionCompleted)) { notification in
                handleSessionCompleted(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchSessionSwept)) { notification in
                handleSessionSwept(notification)
            }
            .onChange(of: viewModel.mode) { _, newMode in
                if newMode.isFullPanel {
                    notificationManager.dismissAll()
                }
                // Kill glow instantly on any mode change to prevent border shrink artifact
                if newMode != .notification && newMode != .compact {
                    glow.cancel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchClosePanel)) { _ in
                withAnimation(closeAnimation) {
                    notificationManager.dismissAll()
                    viewModel.notificationCount = 0
                    viewModel.mode = .compact
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchSessionResumed)) { notification in
                guard let sessionId = notification.object as? String else { return }
                Log.notification.info("Session resumed, dismissing notification session=\(sessionId)")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    notificationManager.dismiss(id: sessionId)
                }
                withAnimation(.easeOut(duration: 0.5)) {
                    glow.cancel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchHotKeyJumpNotification)) { _ in
                // ⌥⇧N: toggle notification focus
                if focusController.isFocused {
                    focusController.unfocus(manager: notificationManager)
                } else if notificationManager.hasNotification {
                    focusController.focus(manager: notificationManager)
                } else {
                    // No notifications → expand notch
                    withAnimation(openAnimation) { viewModel.toggle() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchHotKeyJumpTerminal)) { _ in
                // ⌥⇧J: jump to current session detail's terminal
                if case .sessionDetail(let sessionId) = viewModel.mode,
                   let session = sessionManager.session(for: sessionId) {
                    TerminalJumper.jump(pid: session.pid, tty: session.tty)
                }
            }
            .onChange(of: notificationManager.items.count) { _, count in
                if focusController.isFocused, count > 0 {
                    focusController.clampIndex(maxCount: count)
                }
                if count == 0, viewModel.mode == .notification {
                    if focusController.isFocused { focusController.unfocus(manager: notificationManager) }
                    withAnimation(.easeOut(duration: 0.5)) {
                        glow.cancel()
                        viewModel.notificationCount = 0
                        viewModel.mode = .compact
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.notificationCount = count
                    }
                }
            }
    }

    // MARK: - Handlers

    private func handleSessionCompleted(_ notification: Notification) {
        guard let sessionId = notification.object as? String,
              let userInfo = notification.userInfo
        else { return }

        Log.notification.info("Completion flare for session=\(sessionId)")
        let projectName = userInfo["projectName"] as? String
        glow.trigger(color: .green, label: projectName)

        guard viewModel.mode == .compact || viewModel.mode == .notification
        else { return }

        let pid = (userInfo["pid"] as? NSNumber)?.int32Value
        let ttyVal = userInfo["tty"] as? String
        let item = SessionNotificationBuilder.completionItem(
            sessionId: sessionId,
            userInfo: userInfo,
            onTap: notificationTapAction(sessionId: sessionId, pid: pid, tty: ttyVal)
        )
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            notificationManager.enqueue(item)
            viewModel.mode = .notification
        }
    }

    private func handleSessionSwept(_ notification: Notification) {
        guard let sessionId = notification.object as? String,
              let userInfo = notification.userInfo,
              viewModel.mode == .compact || viewModel.mode == .notification
        else { return }

        let item = SessionNotificationBuilder.sweptItem(sessionId: sessionId, userInfo: userInfo)
        glow.trigger(color: .orange)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            notificationManager.enqueue(item)
            viewModel.mode = .notification
        }
    }

    private func notificationTapAction(sessionId: String, pid: Int32?, tty: String?) -> () -> Void {
        return { [weak viewModel] in
            switch Defaults[.notificationTapAction] {
            case .jumpToTerminal:
                TerminalJumper.jump(pid: pid, tty: tty)
            case .openSessionDetail:
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    viewModel?.showSession(sessionId)
                }
            }
        }
    }
}

extension View {
    /// `agentNotch*` 系の通知と state 変更を一括で dispatch する。
    func notchEventRouter(
        viewModel: NotchViewModel,
        notificationManager: NotchNotificationManager,
        glow: CompletionGlowController,
        focusController: NotificationFocusController,
        sessionManager: SessionManager
    ) -> some View {
        modifier(NotchEventRouter(
            viewModel: viewModel,
            notificationManager: notificationManager,
            glow: glow,
            focusController: focusController,
            sessionManager: sessionManager
        ))
    }
}
