import AgentNotchCore
import Defaults
import SwiftUI

/// Collects SessionCardView's callbacks. All default to no-ops.
struct SessionCardActions {
    var tap: () -> Void = {}
    var remove: () -> Void = {}
    var togglePin: () -> Void = {}
    var toggleMute: () -> Void = {}
    var toggleDone: () -> Void = {}
    var selectTitleDisplayPreference: (SessionTitleDisplayPreference) -> Void = { _ in }
}

/// Chooses the title and one contextual line shown on a session card.
///
/// The title is the durable identity of a session. The contextual line deliberately favours the
/// most actionable or recent state over the user prompt: a request for approval, active work, or
/// a completion summary is more useful while scanning cards than repeating the title.
enum SessionCardPresentation {
    struct Content: Equatable {
        let titleText: String?
        let activityText: String
        let workText: String?
        let metadataText: String?
    }

    struct Historical: Equatable {
        let activityText: String
        let metadataText: String?
    }

    static func content(
        session: UnifiedSession,
        promptSource: CardPromptSource,
        titleDisplayPreference: SessionTitleDisplayPreference? = nil
    ) -> Content {
        let title = titleText(
            session: session,
            source: promptSource,
            preference: titleDisplayPreference
        )

        if let historical = historical(session: session) {
            return Content(
                titleText: title,
                activityText: historical.activityText,
                workText: workText(session: session),
                metadataText: historical.metadataText
            )
        }

        return Content(
            titleText: title,
            activityText: liveActivityText(session: session, titleText: title),
            workText: workText(session: session),
            metadataText: nil
        )
    }

    static func historical(
        session: UnifiedSession
    ) -> Historical? {
        let prefix: String
        switch session.presence {
        case .restored:
            prefix = L("Last seen")
        case .inactive:
            prefix = L("Process ended")
        case .live:
            return nil
        }

        let status = localizedStatus(session.lastKnownStatus ?? session.status)
        let history = [prefix, status]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        // Completion summaries are durable and remain the useful answer after a restart. For
        // every other historical state, the state itself is the only trustworthy context.
        if session.lastKnownStatus == .done,
            let message = nonEmpty(session.lastAssistantMessage)
        {
            return Historical(activityText: flatten(message), metadataText: history)
        }

        return Historical(activityText: history, metadataText: nil)
    }

    /// The per-session choice can promote the latest prompt above an agent title that has become
    /// stale. Without an explicit choice, the agent title remains primary and the app-level prompt
    /// preference fills the gap for agents or older sessions that do not expose one.
    static func titleText(
        session: UnifiedSession,
        source: CardPromptSource,
        preference: SessionTitleDisplayPreference?
    ) -> String? {
        if preference == .latestPrompt,
            let prompt = nonEmpty(session.lastUserPrompt ?? session.firstUserPrompt)
        {
            return flatten(prompt)
        }
        if let title = nonEmpty(session.sessionTitle) {
            return flatten(title)
        }
        return promptText(session: session, source: source).map(flatten)
    }

    /// A title can be selected in the card menu only once the agent has supplied non-blank text.
    /// Keeping this test alongside title selection prevents the menu and displayed title from
    /// disagreeing about availability.
    static func hasSessionTitle(_ session: UnifiedSession) -> Bool {
        nonEmpty(session.sessionTitle) != nil
    }

    static func promptText(session: UnifiedSession, source: CardPromptSource) -> String? {
        switch source {
        case .firstUserMessage:
            session.firstUserPrompt
        case .lastUserMessage:
            session.lastUserPrompt ?? session.firstUserPrompt
        }
    }

    static func countdownPermission(for session: UnifiedSession) -> PermissionRequest? {
        guard case .permission(let permission) = session.currentInterruption,
            permission.canRespond
        else { return nil }
        return permission
    }

    static func flatten(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func liveActivityText(session: UnifiedSession, titleText: String?) -> String {
        // 1. User action always wins: this is the state that must be noticed before any summary.
        if case .permission(let permission) = session.currentInterruption {
            let value = permission.toolInput.values.first ?? ""
            let prefix = permission.isPlanReview ? L("Awaiting plan approval") : L("Awaiting approval")
            return value.isEmpty
                ? L("\(prefix) — \(permission.toolName)")
                : L("\(prefix) — \(permission.toolName) \(value)")
        }
        if case .question = session.currentInterruption { return L("Awaiting an answer") }

        // 2. A failure or current work describes what needs attention now.
        if session.status == .error { return L("Error — the response was interrupted") }
        if session.runningSubagentCount > 0 {
            return L("Running \(session.runningSubagentCount) subagents")
        }
        if let tool = session.currentTool, tool.status == .running {
            return tool.summary.isEmpty ? tool.name : "\(tool.name) — \(tool.summary)"
        }

        // 3. Finished work gets its final assistant message, including after an in-process update.
        if session.status == .done {
            if let message = nonEmpty(session.lastAssistantMessage) { return flatten(message) }
            return L("Done")
        }

        // 4. On a quiet live session, the latest prompt gives the best indication of the work that
        // followed the original title. Do not repeat it when it is already the title fallback.
        if let prompt = nonEmpty(session.lastUserPrompt) {
            let flattened = flatten(prompt)
            if flattened != titleText { return flattened }
        }
        return session.status.label
    }

    /// The final card row describes work owned by the session. A live subagent wins over the task
    /// list because it is doing work concurrently; otherwise the in-progress task says what the
    /// parent agent is currently advancing.
    private static func workText(session: UnifiedSession) -> String? {
        let runningSubagents = session.subagents.filter { $0.status == .running }
        if !runningSubagents.isEmpty {
            let names = runningSubagents.prefix(3).map(\.agentType)
            let overflow = runningSubagents.count - names.count
            let suffix = overflow > 0 ? " +\(overflow)" : ""
            return "\(L("Subagents")) — \(names.joined(separator: ", "))\(suffix)"
        }

        if let task = session.tasks.first(where: { $0.status == .inProgress }) {
            return "\(L("Tasks")) — \(task.subject)"
        }

        return nil
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private static func localizedStatus(_ status: SessionStatus) -> String {
        switch status {
        case .starting: L("Starting")
        case .idle: L("Idle")
        case .thinking: L("Thinking")
        case .toolRunning: L("Running")
        case .subagentRunning: L("Subagent")
        case .permissionWaiting: L("Approval")
        case .compacting: L("Compacting")
        case .done: L("Done")
        case .error: L("Error")
        case .completed: L("Ended")
        }
    }
}

/// One row of the session list.
///
/// # Layout
/// ```
/// ┌──────────────────────────────────────────────────────┐
/// │ [glyph] Persist session cards                     92s │
/// │   C     sample-web  feat/ios-onboarding  wt-ios [PLAN]│
/// │         Awaiting approval — Bash rm -rf .next/cache   │
/// │         ◧◧◧◨ Tasks — Persist card data · 2/4 TASKS    │
/// └──────────────────────────────────────────────────────┘
/// ```
/// - Left column: state glyph (13×13) + one agent character. **Only the left column's dots
///   carry state**
/// - Middle column: session title → repo/branch/worktree → current context → work + machine values
/// - Right column: time remaining or relative time + the options menu
///
/// # No approving from the list
/// Approve/deny lives only on the detail screen (`PermissionBanner`). The list is where you scan
/// several sessions, and lining up irreversible-decision buttons row by row raises the risk of a
/// mistaken tap in proportion to the density. The list's job stops at showing which session is
/// waiting for approval (glyph, activity text, countdown).
///
/// # Choosing typefaces
/// Text that describes the session (title, activity, work) is native; machine-emitted values
/// (repository, branch, worktree, tokens, times) are mono.
struct SessionCardView: View {
    let session: UnifiedSession
    var userState: SessionUserState = .empty
    var isUserDone: Bool = false
    var isKeyboardFocused: Bool = false
    var actions: SessionCardActions = SessionCardActions()

    @Default(.textSize) private var textSize
    @Default(.cardPromptSource) private var promptSource
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// Size of the left column's state glyph.
    private let glyphSize: CGFloat = 26

    /// The pending approval whose response deadline gets a countdown.
    /// canRespond=false (expired, or terminal-only responses as with Codex) has no deadline and
    /// is excluded.
    private var pendingPermission: PermissionRequest? {
        SessionCardPresentation.countdownPermission(for: session)
    }

    private var isAlert: Bool {
        session.hasPendingInterruptions
    }

    private var canJumpToTerminal: Bool {
        session.isTerminalJumpAvailable
    }

    private var canJumpToCodexApp: Bool {
        CodexAppJumper.canJump(to: session)
    }

    private var canJumpToClaudeApp: Bool {
        ClaudeDesktopJumper.canJump(to: session)
    }

    private var primaryJumpDestination: SessionDestinationJumper.Destination? {
        SessionDestinationJumper.destination(
            for: session,
            canJumpToCodexApp: { _ in canJumpToCodexApp },
            canJumpToClaudeApp: { _ in canJumpToClaudeApp }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftColumn
            middleColumn
            rightColumn
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .panelCard(cornerRadius: DSShape.cell, tint: cardTint, border: cardBorder)
        .contentShape(Rectangle())
        .onTapGesture { actions.tap() }
    }

    private var cardTint: Color {
        DSColors.ink.opacity(0.04)
    }

    private var cardBorder: Color {
        if isKeyboardFocused { return DSColors.ink.opacity(0.58) }
        return DSColors.lineDefault
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 6) {
            StateGlyphView(
                state: session.glyphState,
                size: glyphSize,
                animationStartTime: session.doneAt
            )
            // The official logo rather than a single character (C / X). It goes against the
            // wings' "only glyphs go here" idea, but a logo reads faster than a letter and never
            // blends into the state glyph.
            // The color stays official even when done or read: the logo identifies which agent
            // it is, and dimming it reads as a color change — a different thing. How recessed
            // the card is comes from the state glyph and the text color alone.
            AgentMark(
                agentType: session.agentType,
                size: s(10)
            )
        }
        .frame(width: glyphSize)
    }

    // MARK: - Middle column

    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            titleRow
            identityRow
            activityRow
            metaRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                if cardContent.titleText == nil {
                    sessionIndicators
                }

                Text(repoDisplayName)
                    .font(DSTypography.Native.monoFootnote(textSize.scale, weight: .medium))
                    .foregroundStyle(
                        session.status == .done || isUserDone
                            ? DSColors.ink.opacity(0.58) : DSColors.inkDim
                    )
                    .lineLimit(1)
            }

            if let branch = session.gitBranch {
                Text(branch)
                    .font(DSTypography.mono(s(10)))
                    .foregroundStyle(DSColors.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let worktree = session.worktreeName {
                Text(worktree)
                    .font(DSTypography.mono(s(10)))
                    .foregroundStyle(DSColors.signalThinking.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            badges

            Spacer(minLength: 0)
        }
    }

    /// The session title is the card's primary label. Repository, branch, and worktree follow on
    /// their own row as operational context rather than competing with the user's task.
    @ViewBuilder
    private var titleRow: some View {
        if let title = cardContent.titleText {
            HStack(alignment: .center, spacing: 7) {
                sessionIndicators

                Text(title)
                    .font(DSTypography.Native.callout(textSize.scale, weight: .semibold))
                    .foregroundStyle(
                        session.status == .done || isUserDone
                            ? DSColors.ink.opacity(0.7) : DSColors.ink
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var sessionIndicators: some View {
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
    }

    /// The PLAN / TEAM / PIN badges, shown as small bordered or filled chips.
    @ViewBuilder
    private var badges: some View {
        if session.permissionMode == .plan {
            badge(L("Plan").uppercased(), color: DSColors.signalPlan, bordered: true)
        }
        if let team = session.teamName {
            badge(
                "\(L("Team").uppercased()) · \(shortTeamName(team))",
                color: DSColors.inkDim,
                bordered: false
            )
        }
        if userState.pinned {
            badge(L("Pin").uppercased(), color: DSColors.inkMute, bordered: false)
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
                DSShape.rounded(DSShape.tag)
                    .stroke(bordered ? color.opacity(0.5) : .clear, lineWidth: 0.5)
            )
            .clipShape(DSShape.rounded(DSShape.tag))
            .fixedSize()
    }

    /// The highest-priority context below the session title, said in a single line.
    private var activityRow: some View {
        Text(activityText)
            .font(DSTypography.Native.subheadline(textSize.scale))
            .foregroundStyle(activityColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var cardContent: SessionCardPresentation.Content {
        SessionCardPresentation.content(
            session: session,
            promptSource: promptSource,
            titleDisplayPreference: userState.titleDisplayPreference
        )
    }

    private var activityText: String {
        cardContent.activityText
    }

    private var activityColor: Color {
        if session.presence != .live { return DSColors.inkMute }
        if isAlert { return DSColors.ink.opacity(0.75) }
        if session.status == .error { return DSColors.signalError.opacity(0.85) }
        if session.status == .done || isUserDone { return DSColors.inkDim }
        return DSColors.ink.opacity(0.55)
    }

    /// The final row: subagent or in-progress task detail, then glyphs and machine values.
    ///
    /// The display policy chooses one human-readable work detail; glyphs retain the complete task
    /// or subagent shape for quick scanning, while the remaining space carries machine values.
    @ViewBuilder
    private var metaRow: some View {
        let hasGlyphs =
            session.runningSubagentCount > 0 || !session.subagents.isEmpty || !session.tasks.isEmpty
        if hasGlyphs || cardContent.workText != nil || !metaText.isEmpty {
            HStack(spacing: 8) {
                if session.runningSubagentCount > 0 || !session.subagents.isEmpty {
                    subagentGlyphs
                } else if !session.tasks.isEmpty {
                    taskGlyphs
                }
                if let workText = cardContent.workText {
                    Text(workText)
                        .font(DSTypography.Native.caption(textSize.scale))
                        .foregroundStyle(DSColors.inkMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
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

    /// Running subagents are filled diamonds, free slots are outlines. Up to 6, then `+N`.
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

    /// Tasks come in three levels: todo / active / done. Up to 6, then `+N`.
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

    /// A run of machine values such as `2/4 TASKS · 18.2K TOK · $0.42`.
    private var metaText: String {
        var parts: [String] = []
        if let history = cardContent.metadataText {
            parts.append(history)
        }
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
                    hasSessionTitle: SessionCardPresentation.hasSessionTitle(session),
                    // Codex uses the app as its primary destination. Keep the originating terminal
                    // as a secondary route for CLI-only responses without adding another card icon.
                    showTerminalJump: canJumpToCodexApp && canJumpToTerminal,
                    onTogglePin: actions.togglePin,
                    onToggleMute: actions.toggleMute,
                    onToggleDone: actions.toggleDone,
                    onSelectTitleDisplayPreference: actions.selectTitleDisplayPreference,
                    onJumpToTerminal: { TerminalJumper.jump(pid: session.pid, tty: session.tty) },
                    onRemove: actions.remove,
                    // Same 20×20 frame as the destination button directly below — in a
                    // trailing-aligned column, equal frame widths keep them centered.
                    labelSize: 13,
                    labelFrame: CGSize(width: 20, height: 20),
                    symbolName: "ellipsis.circle"
                )
            }

            // Keep one primary destination directly below the menu. A Codex card opens the same
            // technical thread in the desktop app; other cards retain the terminal jump.
            switch primaryJumpDestination {
            case .codexApp:
                codexAppJumpButton
            case .terminal:
                terminalJumpButton
            case .claudeApp:
                claudeAppJumpButton
            case nil:
                EmptyView()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Jump to the terminal. As on the detail screen, it is shown with the terminal app's own
    /// icon so you can see which app you land in. Where the icon is unavailable, it falls back
    /// to a symbol.
    private var terminalJumpButton: some View {
        Button {
            SessionDestinationJumper.jump(to: session)
        } label: {
            Group {
                if let icon = session.terminalAppIcon as? NSImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: s(15), height: s(15))
                } else {
                    Image(systemName: "arrow.right.square")
                        .font(.system(size: s(14), weight: .medium))
                        .foregroundStyle(DSColors.inkDim)
                }
            }
            // The outer frame is pinned to the same 20×20 as the ⋯ (SessionActionMenu's
            // labelFrame). In a trailing-aligned column, a different frame width shifts the
            // horizontal center.
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Jump to Terminal"))
        .accessibilityLabel(L("Jump to Terminal"))
    }

    /// Open this exact local thread in the Codex desktop surface. The frame matches the menu and
    /// terminal buttons so every icon in the trailing column shares one horizontal center.
    private var codexAppJumpButton: some View {
        Button {
            SessionDestinationJumper.jump(to: session)
        } label: {
            appDestinationLabel(
                icon: CodexAppJumper.applicationIcon(for: session),
                fallbackMark: .codex
            )
        }
        .buttonStyle(.plain)
        .help(L("Open in Codex App"))
        .accessibilityLabel(L("Open in Codex App"))
    }

    /// Open this session in the Claude desktop app, which is the surface running it. The frame
    /// matches the other trailing icons so the column keeps one horizontal center.
    private var claudeAppJumpButton: some View {
        Button {
            SessionDestinationJumper.jump(to: session)
        } label: {
            appDestinationLabel(
                icon: ClaudeDesktopJumper.applicationIcon(for: session),
                fallbackMark: .claudeCode
            )
        }
        .buttonStyle(.plain)
        .help(L("Open in Claude App"))
        .accessibilityLabel(L("Open in Claude App"))
    }

    /// An app destination reads as its own icon, the way the terminal jump does. The vendor mark is
    /// only a fallback for when Launch Services has no icon to give.
    private func appDestinationLabel(icon: NSImage?, fallbackMark: AgentType) -> some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: s(15), height: s(15))
            } else {
                AgentMark(
                    agentType: fallbackMark,
                    size: s(15),
                    color: DSColors.inkDim
                )
            }
        }
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }

    /// Seconds remaining until expiry while awaiting approval; otherwise the time relative to
    /// the last activity.
    @ViewBuilder
    private var trailingStatusText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let perm = pendingPermission {
                // The expiry time is derived from the hook's recv timeout (120s).
                // PermissionRequest itself has no expiresAt; expiry is expressed by `canRespond`.
                let expiresAt = perm.timestamp.addingTimeInterval(
                    TimeInterval(HookHandler.recvTimeoutSeconds))
                let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date)))
                Text(verbatim: L("\(remaining)s"))
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

    // MARK: - Helpers

    private var repoDisplayName: String {
        session.originRepoName
            ?? session.worktreeName
            ?? (session.cwd as NSString?)?.lastPathComponent
            ?? L("Session")
    }

    private func shortTeamName(_ team: String) -> String {
        // Team names can be long, since they derive from the leader's session_id — show the head.
        team.count > 10 ? String(team.prefix(8)) : team
    }

    private func shortModel(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20250929", with: "")
            .replacingOccurrences(of: "-latest", with: "")
    }

}

// MARK: - Model → Glyph

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
