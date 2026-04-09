import AgentNotchCore
import Defaults
import SwiftUI

enum NotchMode: Equatable, Sendable, CustomStringConvertible {
    case compact
    case notification
    case expanded
    case sessionDetail(sessionId: String)

    var isSessionDetail: Bool {
        if case .sessionDetail = self { return true }
        return false
    }

    var isFullPanel: Bool {
        switch self {
        case .expanded, .sessionDetail: true
        default: false
        }
    }

    var description: String {
        switch self {
        case .compact: "compact"
        case .notification: "notification"
        case .expanded: "expanded"
        case .sessionDetail(let id): "sessionDetail(\(id.prefix(8)))"
        }
    }
}

@MainActor
@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact {
        didSet {
            if mode != oldValue {
                Log.panel.info("Mode: \(oldValue) → \(mode)")
            }
        }
    }
    var isHovering: Bool = false {
        didSet {
            if isHovering != oldValue {
                Log.panel.debug("Hovering: \(isHovering)")
            }
        }
    }

    var physicalNotchWidth: CGFloat
    var physicalNotchHeight: CGFloat
    var hasActivity: Bool = false

    init(notchSize: CGSize = CGSize(width: 224, height: 38), initialMode: NotchMode = .compact) {
        self.physicalNotchWidth = notchSize.width
        self.physicalNotchHeight = notchSize.height
        self.mode = initialMode
    }

    private let notchCornerMargin: CGFloat = 6

    var sideWidth: CGFloat {
        max(0, physicalNotchHeight - 12) + 10
    }

    private var compactWidth: CGFloat {
        physicalNotchWidth + notchCornerMargin + (2 * sideWidth)
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact:
            return isHovering ? compactWidth + 16 : compactWidth
        case .notification:
            return compactWidth
        case .expanded: return 520
        case .sessionDetail: return 620
        }
    }

    var notificationCount: Int = 0

    private let notificationItemHeight: CGFloat = 42

    var notchHeight: CGFloat {
        switch mode {
        case .compact:
            return isHovering ? physicalNotchHeight + 6 : physicalNotchHeight
        case .notification:
            let count = max(notificationCount, 1)
            return physicalNotchHeight + notificationItemHeight * CGFloat(count) + 6
        case .expanded:
            return 380
        case .sessionDetail:
            return 500
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact, .notification: 6
        case .expanded, .sessionDetail: 12
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .notification: 16
        case .expanded, .sessionDetail: 24
        }
    }

    func toggle() {
        switch mode {
        case .compact, .notification: mode = .expanded
        case .expanded: mode = .compact
        case .sessionDetail: mode = .expanded
        }
    }

    func close() { mode = .compact }
    func showSession(_ id: String) { mode = .sessionDetail(sessionId: id) }
    func backToList() { mode = .expanded }
}

struct NotchContentView: View {
    @State var viewModel: NotchViewModel
    @State private var notificationManager = NotchNotificationManager()
    @ObservedObject var sessionManager: SessionManager
    @Default(.textSize) private var textSize
    @State private var completionGlow: CGFloat = 0
    @State private var glowColor: Color = .green

    init(sessionManager: SessionManager, notchSize: CGSize = CGSize(width: 224, height: 38), initialMode: NotchMode = .compact) {
        self._viewModel = State(initialValue: NotchViewModel(notchSize: notchSize, initialMode: initialMode))
        self.sessionManager = sessionManager
    }

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: viewModel.topCornerRadius,
            bottomCornerRadius: viewModel.bottomCornerRadius
        )
    }

    var body: some View {
        let hasSessions = !sessionManager.activeSessions.isEmpty
        let isExpanded = viewModel.mode.isFullPanel

        VStack(spacing: 0) {
            switch viewModel.mode {
            case .compact, .notification:
                compactContent
            case .expanded, .sessionDetail:
                openedContent
            }
        }
        .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        .background(.black)
        .clipShape(currentNotchShape)
        .overlay(
            CompletionFlare(
                shape: NotchGlowBorder(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                ),
                color: glowColor,
                intensity: completionGlow
            )
            .clipShape(
                NotchOuterMask(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                ),
                style: FillStyle(eoFill: true)
            )
            .allowsHitTesting(false)
        )
        .shadow(color: isExpanded ? .black.opacity(0.6) : .clear, radius: 8)
        .contentShape(currentNotchShape)
        .onHover { hovering in
            guard viewModel.mode == .compact else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.isHovering = hovering
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: viewModel.mode)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isHovering)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            viewModel.hasActivity = hasSessions
        }
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
            guard let sessionId = notification.object as? String,
                  let userInfo = notification.userInfo
            else { return }

            Log.notification.info("Completion flare for session=\(sessionId)")
            triggerCompletionGlow(color: .green)

            guard viewModel.mode == .compact || viewModel.mode == .notification
            else { return }

            let projectName = userInfo["projectName"] as? String ?? "Session"
            let gitBranch = userInfo["gitBranch"] as? String
            let isWT = userInfo["isWorktree"] as? Bool ?? false
            let msg = sanitizedMessage(userInfo["message"] as? String ?? "")
            let pid = (userInfo["pid"] as? NSNumber)?.int32Value
            let ttyVal = userInfo["tty"] as? String
            let itemId = sessionId

            let content = AnyView(
                sessionNotificationContent(
                    icon: AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)),
                    projectName: projectName,
                    gitBranch: gitBranch,
                    isWorktree: isWT,
                    message: msg,
                    onMarqueeComplete: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            notificationManager.requestDismiss(id: itemId)
                        }
                    }
                )
            )
            let item = NotchNotificationManager.Item(
                id: itemId,
                content: content,
                autoDismissAfter: msg.isEmpty ? 7 : nil,
                createdAt: Date(),
                onTap: notificationTapAction(sessionId: sessionId, pid: pid, tty: ttyVal)
            )
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                notificationManager.enqueue(item)
                viewModel.mode = .notification
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentNotchSessionSwept)) { notification in
            guard let sessionId = notification.object as? String,
                  let userInfo = notification.userInfo,
                  viewModel.mode == .compact || viewModel.mode == .notification
            else { return }

            let projectName = userInfo["projectName"] as? String ?? "Session"
            let msg = userInfo["message"] as? String ?? ""
            let itemId = "swept-\(sessionId)"

            let content = AnyView(
                sessionNotificationContent(
                    icon: AnyView(Image(systemName: "trash.circle.fill").foregroundStyle(.orange)),
                    projectName: projectName,
                    gitBranch: nil,
                    message: msg,
                    onMarqueeComplete: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            notificationManager.requestDismiss(id: itemId)
                        }
                    }
                )
            )
            let item = NotchNotificationManager.Item(
                id: itemId,
                content: content,
                autoDismissAfter: msg.isEmpty ? 7 : nil,
                createdAt: Date()
            )
            triggerCompletionGlow(color: .orange)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                notificationManager.enqueue(item)
                viewModel.mode = .notification
            }
        }
        .onChange(of: viewModel.mode) { _, newMode in
            if newMode.isFullPanel {
                notificationManager.dismissAll()
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
            // Dismiss completion notification for this session
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                notificationManager.dismiss(id: sessionId)
            }
            // Cancel completion glow
            withAnimation(.easeOut(duration: 0.5)) {
                completionGlow = 0
            }
        }
        .onChange(of: notificationManager.items.count) { _, count in
            if count == 0, viewModel.mode == .notification {
                // All notifications dismissed — collapse to compact in one animation
                withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
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

    @ViewBuilder
    private var openedContent: some View {
        switch viewModel.mode {
        case .compact, .notification:
            EmptyView()
        case .expanded:
            expandedContent
        case .sessionDetail(let sessionId):
            if let session = sessionManager.session(for: sessionId) {
                SessionDetailView(session: session, sessionManager: sessionManager) {
                    viewModel.backToList()
                }
            } else {
                expandedContent
            }
        }
    }

    // MARK: - Compact

    @ViewBuilder
    private var compactContent: some View {
        let sessions = sessionManager.activeSessions
        let urgentStatus = mostUrgentStatus(sessions)
        let wing = viewModel.sideWidth

        VStack(spacing: 0) {
            // Wing row (status dot + tool name + session count)
            HStack(spacing: 0) {
                // Left wing
                ZStack {
                    if !sessions.isEmpty {
                        StatusIndicator(status: urgentStatus, size: 12)
                    }
                }
                .frame(width: wing, height: viewModel.physicalNotchHeight)

                // Center: tool ticker (fills remaining space between wings)
                ZStack {
                    if let toolName = activeToolName(sessions) {
                        TickerText(
                            text: toolName,
                            font: .system(size: 9, weight: .medium, design: .monospaced),
                            color: .white.opacity(0.6)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: viewModel.physicalNotchHeight)
                .clipped()

                // Right wing: running/total session count (stacked vertically)
                ZStack {
                    let total = sessions.count
                    let running = sessions.filter(\.status.isRunning).count
                    if total > 0 {
                        VStack(spacing: 0) {
                            Text("\(running)")
                                .foregroundStyle(.white.opacity(running > 0 ? 0.75 : 0.35))
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 12, height: 0.5)
                            Text("\(total)")
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
                .frame(width: wing, height: viewModel.physicalNotchHeight)
            }

            // Notification rows (stacked, only in .notification mode)
            if viewModel.mode == .notification {
                VStack(spacing: 0) {
                    ForEach(notificationManager.items) { item in
                        NotificationRowButton(content: item.content) {
                            item.onTap?()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            )
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(width: viewModel.notchWidth)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: viewModel.physicalNotchHeight + 4)

            HStack(spacing: 6) {
                Text("Sessions")
                    .font(.system(size: s(12), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                let count = sessionManager.activeSessions.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: s(9), weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                if !sessionManager.activeSessions.isEmpty {
                    Button {
                        sessionManager.removeAllSessions()
                        sessionManager.notifyChange()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: s(11)))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: s(11)))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            let sessions = sessionManager.activeSessions
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: s(11)))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sessions) { session in
                            SessionCardView(
                                session: session,
                                onTap: {
                                    viewModel.showSession(session.id)
                                },
                                onRemove: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        sessionManager.removeSession(id: session.id)
                                        sessionManager.notifyChange()
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Helpers

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// Reusable content builder for session-related notifications.
    @ViewBuilder
    private func sessionNotificationContent(
        icon: AnyView,
        projectName: String,
        gitBranch: String?,
        isWorktree: Bool = false,
        message: String,
        onMarqueeComplete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                icon.font(.system(size: s(9)))
                Text(projectName)
                    .font(.system(size: s(9), weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                if let branch = gitBranch {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: s(7)))
                        .foregroundStyle(isWorktree ? .cyan.opacity(0.5) : .white.opacity(0.3))
                    Text(branch)
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundStyle(isWorktree ? .cyan.opacity(0.4) : .white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
            }

            if !message.isEmpty {
                MarqueeText(
                    text: message,
                    font: .system(size: s(10), weight: .medium),
                    onCycleComplete: onMarqueeComplete
                )
                .foregroundStyle(.white.opacity(0.55))
                .frame(height: s(14))
            }
        }
    }

    private func activeToolName(_ sessions: [UnifiedSession]) -> String? {
        sessions.lazy
            .compactMap { $0.currentTool }
            .first { $0.status == .running }
            .map(\.name)
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

    private func sanitizedMessage(_ message: String) -> String {
        let text = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }

    private func triggerCompletionGlow(color: Color) {
        glowColor = color
        withAnimation(.easeOut(duration: 0.4)) {
            completionGlow = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 2.5)) {
                completionGlow = 0
            }
        }
    }

    private func mostUrgentStatus(_ sessions: [UnifiedSession]) -> SessionStatus {
        let priority: [SessionStatus] = [
            .permissionWaiting, .error, .toolRunning, .subagentRunning,
            .thinking, .compacting, .done, .idle, .starting, .completed,
        ]
        for status in priority {
            if sessions.contains(where: { $0.status == status }) {
                return status
            }
        }
        return .idle
    }
}
