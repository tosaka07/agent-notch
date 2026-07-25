import AgentNotchCore
import Defaults
import SwiftUI

/// SessionCardView のコールバックを集約。初期値は全て no-op。
struct SessionCardActions {
    var tap: () -> Void = {}
    var remove: () -> Void = {}
    var togglePin: () -> Void = {}
    var toggleMute: () -> Void = {}
    var toggleDone: () -> Void = {}
    /// 承認待ちを一覧から直接承認する。
    var approve: (String) -> Void = { _ in }
    /// 承認待ちを一覧から直接拒否する。
    var deny: (String) -> Void = { _ in }
}

/// セッション一覧の 1 行（Claude Design モック 1b）。
///
/// # レイアウト
/// ```
/// ┌──────────────────────────────────────────────────────┐
/// │ [glyph] tapple-web  feat/ios-onboarding  [PLAN]   92s │
/// │   C     承認待ち — Bash rm -rf .next/cache   [承認][拒否]│
/// │         ◧◧◧◨ 2/4 TASKS · 18.2K TOK · $0.42            │
/// └──────────────────────────────────────────────────────┘
/// ```
/// - 左列: 状態グリフ（13×13）+ エージェント 1 文字。**状態を持つのは左列のドットだけ**
/// - 中列: repo/branch/バッジ → 活動テキスト → グリフ列 + メタ値
/// - 右列: 残り時間 or 相対時刻 + オプションメニュー、承認待ちなら承認/拒否ボタン
///
/// # 書体の使い分け
/// 構造を語るテキスト（repo 名・活動）は native、機械が出す値（branch・トークン・時刻）は
/// mono。モックがこの使い分けをしているので踏襲する。
struct SessionCardView: View {
    let session: UnifiedSession
    var userState: SessionUserState = .empty
    var isUserDone: Bool = false
    var actions: SessionCardActions = SessionCardActions()

    @Default(.textSize) private var textSize
    @Default(.cardPromptSource) private var promptSource
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// 左列の状態グリフのサイズ。
    private let glyphSize: CGFloat = 26

    /// 承認待ちで、かつ一覧から応答できる状態か。
    private var pendingPermission: PermissionRequest? {
        session.pendingPermissions.first { $0.canRespond }
    }

    private var isAlert: Bool {
        session.status == .permissionWaiting || session.pendingQuestion != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftColumn
            middleColumn
            rightColumn
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorder, lineWidth: 0.5)
        )
        .opacity(isUserDone ? 0.72 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { actions.tap() }
    }

    /// 割り込み中は少し明るく、完了・ユーザー既読は沈める（モックの .055 / .035 / .02）。
    private var cardBackground: Color {
        if isAlert { return DSColors.ink.opacity(0.055) }
        if isUserDone || session.status == .done { return DSColors.ink.opacity(0.02) }
        return DSColors.ink.opacity(0.035)
    }

    private var cardBorder: Color {
        guard isAlert else { return .clear }
        return session.pendingPermissions.first?.isPlanReview == true
            ? DSColors.signalPlan.opacity(0.28)
            : DSColors.signalAlert.opacity(0.28)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 6) {
            StateGlyphView(
                state: session.glyphState,
                size: glyphSize,
                animationStartTime: session.doneAt
            )
            Text(session.agentType.glyphLetter)
                .font(DSTypography.mono(s(7), weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(agentLetterColor)
        }
        .frame(width: glyphSize)
    }

    private var agentLetterColor: Color {
        if isAlert { return DSColors.signalAlert }
        if session.status == .done || isUserDone { return DSColors.inkMute }
        return DSColors.inkDim
    }

    // MARK: - Middle column

    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            identityRow
            activityRow
            metaRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if userState.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: s(7)))
                    .foregroundStyle(DSColors.signalAlert.opacity(0.7))
                    .rotationEffect(.degrees(45))
            }
            if userState.muted {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: s(7)))
                    .foregroundStyle(DSColors.inkMute)
            }

            Text(repoDisplayName)
                .font(DSTypography.Native.callout(textSize.scale, weight: .semibold))
                .foregroundStyle(session.status == .done || isUserDone ? DSColors.ink.opacity(0.75) : DSColors.ink)
                .lineLimit(1)

            if let branch = session.gitBranch {
                Text(branch)
                    .font(DSTypography.mono(s(10)))
                    .foregroundStyle(session.worktreeName != nil ? DSColors.signalThinking.opacity(0.5) : DSColors.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            badges

            Spacer(minLength: 0)
        }
    }

    /// PLAN / TEAM / PIN のバッジ。枠線 or 塗りの小さなチップで出す。
    @ViewBuilder
    private var badges: some View {
        if session.permissionMode == .plan {
            badge("PLAN", color: DSColors.signalPlan, bordered: true)
        }
        if let team = session.teamName {
            badge("TEAM · \(shortTeamName(team))", color: DSColors.inkDim, bordered: false)
        }
        if userState.pinned {
            badge("PIN", color: DSColors.inkMute, bordered: false)
        }
    }

    private func badge(_ text: String, color: Color, bordered: Bool) -> some View {
        Text(text)
            .font(DSTypography.mono(s(8), weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(bordered ? Color.clear : DSColors.ink.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(bordered ? color.opacity(0.5) : .clear, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .fixedSize()
    }

    /// いま何をしているか。1 行で言い切る（モックは native フォントの 1 行）。
    private var activityRow: some View {
        Text(activityText)
            .font(DSTypography.Native.subheadline(textSize.scale))
            .foregroundStyle(activityColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var activityText: String {
        if let perm = session.pendingPermissions.first {
            let value = perm.toolInput.values.first ?? ""
            let prefix = perm.isPlanReview ? "plan の承認待ち" : "承認待ち"
            return value.isEmpty ? "\(prefix) — \(perm.toolName)" : "\(prefix) — \(perm.toolName) \(value)"
        }
        if session.pendingQuestion != nil { return "質問に回答待ち" }
        if session.status == .error { return "エラー — 応答が中断されました" }
        if session.runningSubagentCount > 0 {
            let names = session.subagents.filter { $0.status == .running }.map(\.agentType)
            return "subagent ×\(session.runningSubagentCount) 実行中 — \(names.prefix(3).joined(separator: ", "))"
        }
        if let tool = session.currentTool, tool.status == .running {
            return tool.summary.isEmpty ? tool.name : "\(tool.name) — \(tool.summary)"
        }
        if session.status == .done {
            if let msg = session.lastAssistantMessage, !msg.isEmpty {
                return flatten(msg)
            }
            return "完了"
        }
        if let prompt = promptText, !prompt.isEmpty { return flatten(prompt) }
        return session.status.label
    }

    private var activityColor: Color {
        if isAlert { return DSColors.ink.opacity(0.75) }
        if session.status == .error { return DSColors.signalError.opacity(0.85) }
        if session.status == .done || isUserDone { return DSColors.inkDim }
        return DSColors.ink.opacity(0.55)
    }

    private var promptText: String? {
        switch promptSource {
        case .firstUserMessage: session.firstUserPrompt ?? session.sessionTitle
        case .lastUserMessage: session.lastUserPrompt ?? session.firstUserPrompt ?? session.sessionTitle
        }
    }

    /// グリフ列 + 機械値のメタ行。
    ///
    /// グリフは「subagent が動いていれば subagent、そうでなければ task」を出す。
    /// タスク名のテキストは出さない（一覧はスキャンする場所なので、名前は詳細で見る）。
    @ViewBuilder
    private var metaRow: some View {
        let hasGlyphs = session.runningSubagentCount > 0 || !session.subagents.isEmpty || !session.tasks.isEmpty
        if hasGlyphs || !metaText.isEmpty {
            HStack(spacing: 8) {
                if session.runningSubagentCount > 0 || !session.subagents.isEmpty {
                    subagentGlyphs
                } else if !session.tasks.isEmpty {
                    taskGlyphs
                }
                if !metaText.isEmpty {
                    Text(metaText)
                        .font(DSTypography.mono(s(9)))
                        .tracking(0.5)
                        .foregroundStyle(DSColors.inkMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 実行中の subagent は塗りの菱形、空き枠は輪郭。最大 6 個 + `+N`。
    private var subagentGlyphs: some View {
        let running = session.subagents.filter { $0.status == .running }.count
        let total = min(6, max(running, min(session.subagents.count, 6)))
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                GlyphView(
                    bitmap: index < running
                        ? Glyph.subagentRunning()
                        : Glyph.subagentIdle()
                )
            }
            if running > 6 {
                Text("+\(running - 6)")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                    .fixedSize()
            }
        }
    }

    /// タスクは未着手 / 進行中 / 完了の 3 段。最大 6 個 + `+N`。
    private var taskGlyphs: some View {
        HStack(spacing: 4) {
            ForEach(session.tasks.prefix(6)) { task in
                GlyphView(bitmap: Glyph.task(task.glyph, color: task.glyphColor))
            }
            if session.tasks.count > 6 {
                Text("+\(session.tasks.count - 6)")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                    .fixedSize()
            }
        }
    }

    /// `2/4 TASKS · 18.2K TOK · $0.42` のような機械値の列。
    private var metaText: String {
        var parts: [String] = []
        if !session.tasks.isEmpty {
            let done = session.tasks.filter { $0.status == .completed }.count
            parts.append("\(done)/\(session.tasks.count) TASKS")
        }
        if let model = session.model {
            parts.append(shortModel(model).uppercased())
        }
        let tokens = session.totalInputTokens + session.totalOutputTokens
        if tokens > 0 {
            parts.append("\(TokenFormatter.format(tokens)) TOK")
        }
        if session.estimatedCost > 0 {
            parts.append(CostCalculator.formatCost(session.estimatedCost))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                trailingStatusText
                SessionActionMenu(
                    userState: userState,
                    isUserDone: isUserDone,
                    showTerminalJump: session.pid != nil || session.tty != nil,
                    onTogglePin: actions.togglePin,
                    onToggleMute: actions.toggleMute,
                    onToggleDone: actions.toggleDone,
                    onJumpToTerminal: { TerminalJumper.jump(pid: session.pid, tty: session.tty) },
                    onRemove: actions.remove,
                    labelSize: 12,
                    labelFrame: CGSize(width: 20, height: 20),
                    symbolName: "ellipsis.circle"
                )
            }

            if let perm = pendingPermission {
                approvalButtons(for: perm)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 承認待ちなら失効までの残り秒、それ以外は最終活動からの相対時刻。
    @ViewBuilder
    private var trailingStatusText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let perm = pendingPermission {
                // 失効時刻は hook の recv timeout（120s）から算出する。
                // PermissionRequest 自体は expiresAt を持たない（`canRespond` で失効を表す）。
                let expiresAt = perm.timestamp.addingTimeInterval(TimeInterval(HookHandler.recvTimeoutSeconds))
                let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date)))
                Text("\(remaining)s")
                    .font(DSTypography.mono(s(10), weight: .semibold))
                    .foregroundStyle(remaining <= 30 ? DSColors.signalAlert : DSColors.inkDim)
                    .monospacedDigit()
            } else {
                Text(RelativeTimeFormatter.format(since: session.lastActivityAt, relativeTo: context.date))
                    .font(DSTypography.mono(s(10)))
                    .foregroundStyle(DSColors.inkMute)
            }
        }
    }

    /// 一覧から直接承認/拒否する。詳細画面と同じ誤タップガード（`armedAfter`）を掛ける。
    private func approvalButtons(for perm: PermissionRequest) -> some View {
        HStack(spacing: 5) {
            Button {
                actions.approve(perm.toolUseId)
            } label: {
                Text("承認")
                    .font(DSTypography.Native.caption(textSize.scale, weight: .semibold))
                    .padding(.horizontal, 11)
                    .frame(height: 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(DSColors.signalAlert)
            .foregroundStyle(Color.black.opacity(0.85))

            Button {
                actions.deny(perm.toolUseId)
            } label: {
                Text("拒否")
                    .font(DSTypography.Native.caption(textSize.scale, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .armedAfter()
    }

    // MARK: - Helpers

    private var repoDisplayName: String {
        session.originRepoName
            ?? session.worktreeName
            ?? (session.cwd as NSString?)?.lastPathComponent
            ?? "Session"
    }

    private func shortTeamName(_ team: String) -> String {
        // team 名はリーダーの session_id 由来で長いことがあるので頭だけ見せる。
        team.count > 10 ? String(team.prefix(8)) : team
    }

    private func shortModel(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20250929", with: "")
            .replacingOccurrences(of: "-latest", with: "")
    }

    private func flatten(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }
}

// MARK: - Model → Glyph

extension AgentType {
    /// カード左列に出す 1 文字。翼と同じ「置けるのはグリフだけ」の思想で、
    /// エージェント名は 1 文字に圧縮する（Claude = C / Codex = X）。
    var glyphLetter: String {
        switch self {
        case .claudeCode: "C"
        case .codex: "X"
        case .geminiCLI: "G"
        case .custom: "?"
        }
    }
}

extension AgentTask {
    var glyph: Glyph.TaskGlyph {
        switch status {
        case .pending: .todo
        case .inProgress: .active
        case .completed: .done
        }
    }

    var glyphColor: Color {
        switch status {
        case .pending: DSColors.inkMute
        case .inProgress: DSColors.signalThinking
        case .completed: DSColors.inkDim
        }
    }
}
