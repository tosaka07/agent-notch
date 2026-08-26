import AgentNotchCore
import Defaults
import SwiftUI

/// ViewModifier that dispatches `agentNotch*` NotificationCenter messages and
/// state `onChange` handlers in one place, so the root view keeps a single
/// readable inventory of its side effects.
struct NotchEventRouter: ViewModifier {
    let viewModel: NotchViewModel
    let notificationManager: NotchNotificationManager
    let glow: CompletionGlowController
    let focusController: NotificationFocusController
    @ObservedObject var sessionManager: SessionManager
    let keyboardInteraction: KeyboardInteractionController

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
                        viewModel.showIncomingInterruption(
                            sessionId, sessionManager: sessionManager)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchSessionCompleted)) {
                notification in
                handleSessionCompleted(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchSessionSwept)) { notification in
                handleSessionSwept(notification)
            }
            .onChange(of: viewModel.mode) { _, newMode in
                if newMode.isFullPanel {
                    notificationManager.dismissAll()
                }
                if newMode == .compact {
                    keyboardInteraction.disengage()
                }
                // Kill glow instantly on any mode change to prevent border shrink artifact
                if newMode != .notification && newMode != .compact {
                    glow.cancel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentNotchClosePanel)) { _ in
                keyboardInteraction.disengage()
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
            .onReceive(keyboardInteraction.commands) { event in
                handleKeyboardCommand(event.command)
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
        // Skip the pill when the open detail view is this very session — the
        // completion is already visible on screen.
        let pill: CompletionPill? = {
            if case .sessionDetail(let id) = viewModel.mode, id == sessionId { return nil }
            return projectName.map { CompletionPill(label: $0, sessionId: sessionId) }
        }()
        glow.trigger(color: .green, pill: pill)

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

    private func handleKeyboardCommand(_ command: KeyboardCommand) {
        switch command {
        case .focusInitial:
            switch viewModel.mode {
            case .compact:
                if notificationManager.hasNotification {
                    withAnimation(openAnimation) {
                        viewModel.mode = .notification
                    }
                    focusController.focus(manager: notificationManager)
                } else {
                    withAnimation(openAnimation) {
                        viewModel.mode = .expanded
                    }
                }
            case .notification:
                if notificationManager.hasNotification {
                    focusController.focus(manager: notificationManager)
                }
            case .expanded, .sessionDetail, .usage:
                break
            }

        case .movePrevious where keyboardInteraction.context == .notification:
            focusController.move(by: -1, manager: notificationManager)

        case .moveNext where keyboardInteraction.context == .notification:
            focusController.move(by: 1, manager: notificationManager)

        case .activate where keyboardInteraction.context == .notification:
            focusController.activate(manager: notificationManager)

        case .back:
            withAnimation(closeAnimation) {
                viewModel.backToList()
            }

        case .closePanel:
            if focusController.isFocused {
                focusController.unfocus(manager: notificationManager)
            }
            keyboardInteraction.disengage()
            withAnimation(closeAnimation) {
                viewModel.close()
            }

        case .jumpToTerminal:
            if case .sessionDetail(let sessionId) = viewModel.mode,
                let session = sessionManager.session(for: sessionId),
                session.isTerminalJumpAvailable,
                TerminalJumper.jump(pid: session.pid, tty: session.tty)
            {
                viewModel.close()
            }

        case .jumpToSessionDestination:
            if case .sessionDetail(let sessionId) = viewModel.mode,
                let session = sessionManager.session(for: sessionId),
                SessionDestinationJumper.jump(to: session)
            {
                viewModel.close()
            }

        case .cancel where keyboardInteraction.context == .notification:
            if focusController.isFocused {
                focusController.unfocus(manager: notificationManager)
            }
            keyboardInteraction.disengage()
            withAnimation(closeAnimation) {
                viewModel.close()
            }

        default:
            break
        }
    }
}

extension View {
    /// Dispatches `agentNotch*` notifications and state changes in one place.
    func notchEventRouter(
        viewModel: NotchViewModel,
        notificationManager: NotchNotificationManager,
        glow: CompletionGlowController,
        focusController: NotificationFocusController,
        sessionManager: SessionManager,
        keyboardInteraction: KeyboardInteractionController
    ) -> some View {
        modifier(
            NotchEventRouter(
                viewModel: viewModel,
                notificationManager: notificationManager,
                glow: glow,
                focusController: focusController,
                sessionManager: sessionManager,
                keyboardInteraction: keyboardInteraction
            ))
    }
}
