import AgentNotchCore
import Defaults
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    @ObservedObject var sessionManager: SessionManager
    var onBack: () -> Void
    /// TEAM セクションの行タップで別セッションの detail へ遷移するためのコールバック。
    var onShowSession: (String) -> Void = { _ in }

    @State private var timeline: [TranscriptEntry] = []
    /// ツールの中身を一括で開くか（Claude Code の verbose トグル相当）。
    @State private var expandTools = false
    @State private var isLoading = true
    @State private var isAtBottom = true
    @State private var isSubagentsExpanded: Bool
    @State private var isTeamExpanded: Bool
    @Default(.textSize) private var textSize
    @Environment(\.permissionActions) private var permissionActions
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }
    private var scale: CGFloat { textSize.scale }

    init(
        session: UnifiedSession,
        sessionManager: SessionManager,
        onBack: @escaping () -> Void,
        onShowSession: @escaping (String) -> Void = { _ in }
    ) {
        self.session = session
        self.sessionManager = sessionManager
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

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Divider()

            collapsibleSections

            timelineContent
                // 割り込み（承認 / 質問）は下端に固定する。safeAreaInset なので
                // タイムラインはバーの下までスクロールでき、**バナーが出てもログが
                // 押し出されない**（読んでいた位置がずれない）。
                .safeAreaInset(edge: .bottom, spacing: 0) { interruptionBar }
                // 割り込みは下から滑り込ませる。突然現れるとログを読んでいる最中に
                // 意識が飛ぶので、動きで「下に足された」ことを伝える。
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: hasInterruption)
        }
        .onAppear { loadTimelineAsync() }
    }

    // MARK: - Interruption bar

    /// 応答が必要なもの（承認 / 質問）を載せる下端固定のバー。
    ///
    /// # なぜモーダルにしないか
    /// 「何を承認するか」の判断材料はログそのもの（直前に何をしていたか）なので、
    /// sheet や alert で覆って文脈を隠すのは逆効果。かつ `NotchPanel` は nonactivating で
    /// key window になれないため sheet と相性が悪い。**非モーダルだが固定**が要件。
    ///
    /// # なぜ下端か
    /// 決定は下（sheet / alert のボタン配置の慣習）。タイムラインは bottom anchor なので、
    /// **承認要求の直前のログがバーの真上に来る** = 文脈と決定が隣接する。
    ///
    /// # 立体感
    /// **帯そのものは透明**で、material・角丸・意味色の縁・影はバナー（カード）側が持つ。
    /// notch パネルの中にもう 1 枚の面が置かれているように見せたいので、帯に面を敷いて
    /// しまうとカードとの二重の面になる。背後のログはカードの外側で透けて見える。
    @ViewBuilder
    private var interruptionBar: some View {
        let permission = session.pendingPermissions.first
        let question = session.pendingQuestion

        if permission != nil || question != nil {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let permission {
                    PermissionBanner(
                        permission: permission,
                        onApprove: {
                            permissionActions.approve(session.id, permission.toolUseId)
                            navigateAfterResolvingIfCleared()
                        },
                        onDeny: {
                            permissionActions.deny(session.id, permission.toolUseId, "Denied via Agent Notch")
                            navigateAfterResolvingIfCleared()
                        },
                        onDismiss: {
                            permissionActions.dismissExpired(session.id, permission.toolUseId)
                            navigateAfterResolvingIfCleared()
                        }
                    )
                }

                if let question {
                    QuestionBanner(
                        questions: question.questions,
                        expiresAt: question.expiresAt,
                        isExpired: question.isExpired,
                        onAnswer: { answers in
                            permissionActions.answerQuestion(session.id, question.toolUseId, answers)
                            // 応答経路が失効していた場合は pendingQuestion が失効表示のまま残る。
                            // その場合はこの画面に留まり、失効バナーをユーザーに見せる（issue #28）。
                            navigateAfterResolvingIfCleared()
                        },
                        onDismiss: {
                            permissionActions.dismissExpired(session.id, question.toolUseId)
                            navigateAfterResolvingIfCleared()
                        }
                    )
                    // toolUseId で View identity を切る。同一セッションで pendingQuestion が
                    // 別の質問セットに差し替わったとき、currentIndex 等の @State を
                    // 引き継いでしまうと questions[currentIndex] が index out of range に
                    // なりうるため、質問セットごとに View を作り直す。
                    .id(question.toolUseId)
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
            }
            // カードとパネル端の間の隙間。浮いている面に見せるには、ヘッダーの
            // 左右余白（20）より内側に置く必要がある。狭いとパネルに貼り付いて見える。
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 応答が必要なものがあるか（バーの出入りアニメーションの駆動値）。
    private var hasInterruption: Bool {
        !session.pendingPermissions.isEmpty || session.pendingQuestion != nil
    }

    /// ヘッダー（モック 1d）。
    ///
    /// `‹ 戻る` + 状態グリフ + 2 行の識別情報（repo/branch/pid と cwd/model/tok/cost）
    /// + ツール一括トグル + ターミナルへ移動。状態を語るのは左のグリフだけ。
    private var header: some View {
        HStack(spacing: DSSpacing.sm) {
            Button { onBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("戻る")

            StateGlyphView(
                state: session.glyphState,
                size: s(24),
                animationStartTime: session.doneAt
            )

            VStack(alignment: .leading, spacing: 2) {
                identityLine
                metaLine
            }

            Spacer(minLength: 0)

            toolsToggle

            if session.pid != nil || session.tty != nil {
                Button {
                    TerminalJumper.jump(pid: session.pid, tty: session.tty)
                } label: {
                    HStack(spacing: 5) {
                        if let icon = session.terminalAppIcon as? NSImage {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: s(14), height: s(14))
                        }
                        Text("ターミナル")
                            .font(DSTypography.Native.caption(scale, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("ターミナルへ移動")
                .accessibilityLabel("ターミナルへ移動")
            }

            actionMenu
        }
    }

    /// 1 行目: repo · branch · pid。
    private var identityLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Text(projectName(session.cwd))
                .font(DSTypography.Native.headline(scale))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let branch = session.gitBranch {
                Text(branch)
                    .font(DSTypography.Native.monoCaption(scale))
                    .foregroundStyle(session.worktreeName != nil ? Color.cyan.opacity(0.7) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let pid = session.pid {
                Text("pid \(pid)")
                    .font(DSTypography.Native.monoCaption(scale))
                    .foregroundStyle(.tertiary)
            }
            if session.permissionMode == .plan {
                Text("PLAN")
                    .font(DSTypography.mono(s(8), weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(DSColors.signalPlan)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(DSColors.signalPlan.opacity(0.5), lineWidth: 0.5)
                    )
            }
        }
    }

    /// 2 行目: cwd · エージェント · モデル · トークン · コスト（機械値なので mono）。
    private var metaLine: some View {
        Text(metaLineText)
            .font(DSTypography.Native.monoCaption2(scale))
            .tracking(0.4)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var metaLineText: String {
        var parts: [String] = []
        if let cwd = session.cwd {
            parts.append(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        }
        parts.append(session.agentType.displayName.uppercased())
        if let model = session.model {
            parts.append(model.replacingOccurrences(of: "claude-", with: "").uppercased())
        }
        let tokens = session.totalInputTokens + session.totalOutputTokens
        if tokens > 0 { parts.append("\(TokenFormatter.format(tokens)) TOK") }
        if session.estimatedCost > 0 { parts.append(CostCalculator.formatCost(session.estimatedCost)) }
        return parts.joined(separator: " · ")
    }

    /// ツールの中身を一括で開く / 畳むトグル。
    ///
    /// チャットとツールは 1 本のタイムラインに混ぜてあり、ツールは既定で 1 行に畳んである。
    /// 「全部開いて追いたい」ときのために一括トグルを置く（Claude Code の verbose 表示相当）。
    /// パネルは nonactivating で key window になれないため、ショートカットは効かない環境が
    /// あることを前提にボタンを主たる操作にしている。
    private var toolsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expandTools.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expandTools ? "chevron.down.square" : "chevron.right.square")
                    .font(.system(size: s(10), weight: .medium))
                Text("TOOLS")
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(0.8)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut("o", modifiers: .control)
        .help(expandTools ? "ツールの中身を畳む（⌃O）" : "ツールの中身を開く（⌃O）")
        .accessibilityLabel(expandTools ? "ツールの中身を畳む" : "ツールの中身を開く")
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

    // MARK: - Subagents / Team (collapsible sections)

    @ViewBuilder
    private var collapsibleSections: some View {
        if !session.subagents.isEmpty || session.teamName != nil {
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
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

    // MARK: - Timeline

    /// チャットとツール実行を時系列で混ぜた 1 本のタイムライン。
    /// ツールは既定で 1 行に畳んであり、行のクリックかヘッダーの一括トグルで開く。
    @ViewBuilder
    private var timelineContent: some View {
        if timeline.isEmpty && isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)

                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(timeline) { item in
                            switch item {
                            case .message(let entry):
                                ChatMessageView(entry: entry, agentType: session.agentType)
                                    .id(item.id)
                            case .tool(let entry):
                                ToolLogRow(entry: entry, expandAll: expandTools).id(item.id)
                            }
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
                .onChange(of: timeline.count) { _, _ in
                    if isAtBottom { scrollToBottom(proxy) }
                }
                .onReceive(sessionManager.objectWillChange) {
                    loadTimelineAsync()
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

    /// transcript を読んでタイムラインを組み立てる（重い I/O なので off-MainActor）。
    private func loadTimelineAsync(then scrollToEnd: Bool = false, proxy: ScrollViewProxy? = nil) {
        guard let path = session.transcriptPath else {
            isLoading = false
            return
        }
        Task { @MainActor in
            let entries = await Task.detached {
                TranscriptReader.readTimeline(path: path, tail: 60)
            }.value
            timeline = entries
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
