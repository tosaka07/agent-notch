import AgentNotchCore
import Defaults
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var usageCoordinator: UsageCoordinator
    var onBack: () -> Void
    /// TEAM セクションの行タップで別セッションの detail へ遷移するためのコールバック。
    var onShowSession: (String) -> Void = { _ in }

    @State private var chatEntries: [ChatEntry] = []
    @State private var isLoading = true
    @State private var isAtBottom = true
    @State private var isSubagentsExpanded: Bool
    @State private var isTeamExpanded: Bool
    @State private var isUsageExpanded = false
    @Default(.textSize) private var textSize
    @Default(.usageEnabled) private var usageEnabled
    @Environment(\.permissionActions) private var permissionActions
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }
    private var scale: CGFloat { textSize.scale }

    init(
        session: UnifiedSession,
        sessionManager: SessionManager,
        usageCoordinator: UsageCoordinator,
        onBack: @escaping () -> Void,
        onShowSession: @escaping (String) -> Void = { _ in }
    ) {
        self.session = session
        self.sessionManager = sessionManager
        self.usageCoordinator = usageCoordinator
        self.onBack = onBack
        self.onShowSession = onShowSession
        // デフォルトは実行中がある場合のみ展開する。
        _isSubagentsExpanded = State(initialValue: session.runningSubagentCount > 0)
        if let team = session.teamName {
            let hasRunningTeammate = sessionManager.teamSessions(name: team).contains { $0.status.isRunning }
            _isTeamExpanded = State(initialValue: hasRunningTeammate)
        } else {
            _isTeamExpanded = State(initialValue: false)
        }
    }

    /// 右下の常時ゲージに出す「今どれくらいか」の一点情報。
    /// Gemini CLI / Custom や、未取得（nil snapshot）の間は表示しない。
    /// `usageEnabled` OFF の間は、コーディネータが停止済みでも古い snapshot を
    /// 表示に使わない（#38 の「表示しない」という意図を display 層でも担保する）。
    private var primaryUsagePercent: Double? {
        guard usageEnabled else { return nil }
        return usageCoordinator.snapshot?.primaryUsedPercent(for: session.agentType)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Stats bar
            sessionStatsBar
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            Divider()

            collapsibleSections

            // Banners
            if let perm = session.pendingPermissions.first {
                PermissionBanner(
                    permission: perm,
                    onApprove: {
                        permissionActions.approve(session.id, perm.toolUseId)
                        navigateAfterResolvingIfCleared()
                    },
                    onDeny: {
                        permissionActions.deny(session.id, perm.toolUseId, "Denied via Agent Notch")
                        navigateAfterResolvingIfCleared()
                    },
                    onDismiss: {
                        permissionActions.dismissExpired(session.id, perm.toolUseId)
                        navigateAfterResolvingIfCleared()
                    }
                )
                .padding(.horizontal, 14).padding(.top, 8)
            }

            if let q = session.pendingQuestion {
                QuestionBanner(
                    questions: q.questions,
                    expiresAt: q.expiresAt,
                    isExpired: q.isExpired,
                    onAnswer: { answers in
                        permissionActions.answerQuestion(session.id, q.toolUseId, answers)
                        // 応答経路が失効していた場合は pendingQuestion が失効表示のまま残る。
                        // その場合はこの画面に留まり、失効バナーをユーザーに見せる（issue #28）。
                        navigateAfterResolvingIfCleared()
                    },
                    onDismiss: {
                        permissionActions.dismissExpired(session.id, q.toolUseId)
                        navigateAfterResolvingIfCleared()
                    }
                )
                // toolUseId で View identity を切る。同一セッションで pendingQuestion が
                // 別の質問セットに差し替わったとき、currentIndex 等の @State を
                // 引き継いでしまうと questions[currentIndex] が index out of range に
                // なりうるため、質問セットごとに View を作り直す。
                .id(q.toolUseId)
                .padding(.horizontal, 14).padding(.top, 8)
                // Other の自由入力 TextField はパネルが key window でないと
                // キーボード入力を受け付けられない（NotchPanel は既定で canBecomeKey=false）。
                // 表示中だけ key focus を許可し、消えたら戻す（#2）。
                .onAppear {
                    NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: true)
                }
                .onDisappear {
                    NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: false)
                }
            }

            chatTabContent
        }
        .overlay(alignment: .bottomTrailing) {
            if let percent = primaryUsagePercent {
                UsageGauge(usedPercent: percent, size: s(24))
                    .padding(6)
                    .background(
                        reduceTransparency ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial),
                        in: Circle()
                    )
                    .padding(10)
            }
        }
        .onAppear { loadChatAsync() }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.sm) {
            Button { onBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("戻る")

            StatusIndicator(status: session.status, size: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DSSpacing.xs) {
                    Text(session.sessionTitle ?? projectName(session.cwd))
                        .font(DSTypography.Native.headline(scale))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(session.agentType.displayName)
                        .font(DSTypography.Native.caption2(scale, weight: .medium))
                        .foregroundStyle(session.agentType.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(session.agentType.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    if session.sessionTitle != nil {
                        Text(projectName(session.cwd))
                            .font(DSTypography.Native.monoCaption(scale))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 4) {
                    if let model = session.model {
                        Text(model)
                            .foregroundStyle(.tertiary)
                    }
                    if let branch = session.gitBranch {
                        let isWorktree = session.worktreeName != nil
                        if session.model != nil {
                            Text("·")
                                .foregroundStyle(.tertiary)
                        }
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                            .foregroundStyle(isWorktree ? Color.cyan.opacity(0.7) : Color.secondary)
                        Text(branch)
                            .foregroundStyle(isWorktree ? Color.cyan.opacity(0.6) : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(DSTypography.Native.monoCaption2(scale))
            }

            Spacer()

            if session.pid != nil || session.tty != nil {
                Button {
                    TerminalJumper.jump(pid: session.pid, tty: session.tty)
                } label: {
                    HStack(spacing: 5) {
                        VStack(alignment: .trailing, spacing: 1) {
                            if let name = session.terminalAppName {
                                Text(name)
                                    .font(DSTypography.Native.monoCaption2(scale))
                                    .foregroundStyle(.tertiary)
                            }
                            if let tmux = session.tmuxPaneTarget {
                                Text("tmux:\(tmux)")
                                    .font(DSTypography.Native.monoCaption2(scale))
                                    .foregroundStyle(Color.cyan.opacity(0.6))
                            }
                        }
                        if let icon = session.terminalAppIcon as? NSImage {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: s(16), height: s(16))
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .help("Jump to terminal")
                .accessibilityLabel("ターミナルへ移動")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(RelativeTimeFormatter.format(since: session.startedAt, relativeTo: context.date))
                    .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            actionMenu
        }
    }

    // MARK: - Action menu

    private var actionMenu: some View {
        let userState = sessionManager.userState(for: session.id)
        let isUserDone = sessionManager.isUserDone(session)
        return SessionActionMenu(
            userState: userState,
            isUserDone: isUserDone,
            onTogglePin: { sessionManager.setPinned(session.id, !userState.pinned) },
            onToggleMute: { sessionManager.setMuted(session.id, !userState.muted) },
            onToggleDone: {
                isUserDone ? sessionManager.unmarkDone(session.id) : sessionManager.markDone(session.id)
            },
            onRemove: {
                sessionManager.removeSession(id: session.id)
                sessionManager.notifyChange()
                onBack()
            },
            labelSize: s(10)
        )
    }

    // MARK: - Stats Bar

    private var sessionStatsBar: some View {
        HStack(spacing: DSSpacing.md) {
            statItem(icon: "wrench", value: "\(session.toolCallCount)", label: "tools")
            if session.totalInputTokens > 0 || session.totalOutputTokens > 0 {
                statItem(icon: "arrow.down", value: formatTokens(session.totalInputTokens), label: "in")
                statItem(icon: "arrow.up", value: formatTokens(session.totalOutputTokens), label: "out")
                if session.totalCachedTokens > 0 {
                    statItem(icon: "memorychip", value: formatTokens(session.totalCachedTokens), label: "cached")
                }
            }
            Spacer()
            if session.estimatedCost > 0 {
                Text(String(format: "$%.3f", session.estimatedCost))
                    .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(DSTypography.Native.caption2(scale))
                .foregroundStyle(.tertiary)
        }
        .accessibilityLabel("\(label): \(value)")
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Subagents / Team (collapsible sections)

    @ViewBuilder
    private var collapsibleSections: some View {
        if !session.subagents.isEmpty || session.teamName != nil || primaryUsagePercent != nil {
            VStack(alignment: .leading, spacing: 4) {
                if !session.subagents.isEmpty {
                    collapsibleSection(
                        title: "SUBAGENTS",
                        count: session.subagents.count,
                        isExpanded: $isSubagentsExpanded
                    ) {
                        SubagentListView(subagents: session.subagents, fontScale: scale)
                    }
                }
                if let team = session.teamName {
                    let members = sessionManager.teamSessions(name: team)
                    collapsibleSection(
                        title: "TEAM",
                        count: members.count,
                        isExpanded: $isTeamExpanded
                    ) {
                        TeamSection(
                            currentSessionId: session.id,
                            members: members,
                            fontScale: scale,
                            onShowSession: onShowSession
                        )
                    }
                }
                // 右下の UsageGauge は「今どれくらいか」の一点情報のみ。
                // 週次・モデル別などの内訳はここを開いたときだけ見せる。
                if primaryUsagePercent != nil {
                    collapsibleSection(
                        title: "USAGE",
                        count: usageWindowCount,
                        isExpanded: $isUsageExpanded
                    ) {
                        UsageDetailSection(
                            agentType: session.agentType,
                            snapshot: usageCoordinator.snapshot,
                            scale: scale
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    /// USAGE セクションの件数バッジ（表示するウィンドウの数）。
    private var usageWindowCount: Int {
        switch session.agentType {
        case .claudeCode:
            guard let claude = usageCoordinator.snapshot?.claude else { return 0 }
            return [claude.session, claude.weekAllModels, claude.weekModel].compactMap { $0 }.count
        case .codex:
            guard let codex = usageCoordinator.snapshot?.codex else { return 0 }
            return [codex.primary, codex.secondary].compactMap { $0 }.count
        case .geminiCLI, .custom:
            return 0
        }
    }

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(title)
                        .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%02d", min(count, 99)))
                        .font(DSTypography.Native.monoCaption2(scale, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) \(count)件")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded.wrappedValue ? "展開" : "折りたたみ")

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    // MARK: - Chat Tab

    @ViewBuilder
    private var chatTabContent: some View {
        if chatEntries.isEmpty && isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)

                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(chatEntries) { entry in
                            ChatMessageView(entry: entry)
                                .id(entry.id)
                        }

                        if let tool = session.currentTool, tool.status == .running {
                            ActiveToolIndicator(tool: tool)
                                .id("activeTool")
                                .transition(.opacity)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .modifier(ScrollBottomTracker(isAtBottom: $isAtBottom))
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .accessibilityLabel("最新のメッセージへスクロール")
                    }
                }
                .animation(.easeOut(duration: 0.2), value: isAtBottom)
                .onChange(of: chatEntries.count) { _, _ in
                    if isAtBottom { scrollToBottom(proxy) }
                }
                .onReceive(sessionManager.objectWillChange) {
                    loadChatAsync()
                }
            }
        }
    }

    // MARK: - Navigation

    /// 応答/dismiss の結果、このセッションの pending が実際に解消された場合のみ遷移する。
    /// 応答が届けられず失効表示に切り替わった場合はこの画面に留まる（issue #28）。
    private func navigateAfterResolvingIfCleared() {
        let stillPending = session.pendingQuestion != nil || !session.pendingPermissions.isEmpty
        guard !stillPending else { return }
        navigateAfterResolving()
    }

    /// permission / question に応答した直後の遷移。
    /// 他セッションに未回答の question / permission が残っていれば連続でそこへ遷移し、
    /// 無ければ展開一覧（expanded）に戻る（#5）。
    private func navigateAfterResolving() {
        if let next = sessionManager.sortedSessions(order: .urgency).first(where: { other in
            other.id != session.id && (other.pendingQuestion != nil || !other.pendingPermissions.isEmpty)
        }) {
            onShowSession(next.id)
        } else {
            onBack()
        }
    }

    // MARK: - Data Loading

    private func loadChatAsync(then scrollToEnd: Bool = false, proxy: ScrollViewProxy? = nil) {
        guard let path = session.transcriptPath else { return }
        Task { @MainActor in
            let entries = await Task.detached {
                TranscriptReader.read(path: path, tail: 50)
            }.value
            chatEntries = entries
            isLoading = false
            if scrollToEnd, let proxy {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "" }
        return (path as NSString).lastPathComponent
    }
}
