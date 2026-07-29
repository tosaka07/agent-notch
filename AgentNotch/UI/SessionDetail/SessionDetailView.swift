import AgentNotchCore
import AppKit
import Defaults
import SwiftUI

struct SessionDetailView: View {
    /// Ceiling for an open chip's list, against a 500pt session-detail panel.
    /// The log keeps roughly half its height with a chip open.
    private static let workContextMaxHeight: CGFloat = 180

    /// How long the screen stays empty before admitting it is loading.
    ///
    /// Slightly longer than the panel's opening spring (0.42s), for two
    /// reasons. Most transcripts are read and laid out well inside it — 41ms to
    /// 250ms measured — so the usual session never flashes a spinner at all; it
    /// opens, and the log is there. And while that spring runs, the page is
    /// already laid out at its final 620x500 inside a panel that is still
    /// growing, so anything the page centers sits low and to one side of the
    /// glass until the two agree. A spinner is the one thing on this screen
    /// that is centered, so it was the one thing that showed it.
    private static let spinnerDelay: TimeInterval = 0.45

    let session: UnifiedSession
    @ObservedObject var sessionManager: SessionManager
    let physicalNotchHeight: CGFloat
    var onBack: () -> Void
    /// Closes the whole panel after a permission decision succeeds.
    var onClose: () -> Void
    /// Callback for navigating to another session's detail when a row in the
    /// TEAM section is tapped.
    var onShowSession: (String) -> Void = { _ in }
    let keyboardInteraction: KeyboardInteractionController

    @State private var timeline: [TranscriptEntry] = []
    /// Fingerprint of the most recently loaded transcript. It is not re-read
    /// unless this changes.
    @State private var loadedSignature: TranscriptSignature?
    /// Whether a transcript read is in flight. One at a time: the file is
    /// parsed whole, and a second parse of the same bytes only costs a rebuild.
    @State private var isReadingTranscript = false
    /// Whether every tool's contents are revealed at once, equivalent to Claude
    /// Code's verbose display. Held open only while Control is down — see
    /// `KeyboardCommand.peekTools`.
    @State private var expandTools = false
    @State private var isLoading = true
    /// Whether loading has gone on long enough to say so. See `spinnerDelay`.
    @State private var showsSpinner = false
    /// Whether the log is resting on its newest message. The inverted timeline
    /// places newest at its logical origin.
    @State private var isAtNewest = true
    @State private var scrollPosition = ScrollPosition()
    /// The one open work-context chip, if any.
    @State private var expandedWorkContext: WorkContextKind?
    /// A response initiated in this panel. Direct Codex answers resolve asynchronously, so the
    /// queue advances when this ID actually disappears rather than when SEND is pressed.
    @State private var interruptionNavigation = InterruptionNavigationState()
    /// Natural height of each chip's list, before the cap is applied.
    ///
    /// Keyed by chip rather than held as one value, because the measurement
    /// that produced it only arrives when the geometry *changes*: reopening a
    /// chip whose list is the size it was last time never reports again, so a
    /// value cleared in between would stay cleared and the chip would open to
    /// nothing.
    @State private var workContextHeights: [WorkContextKind: CGFloat] = [:]
    @Default(.textSize) private var textSize
    @Environment(\.permissionActions) private var permissionActions
    @Environment(\.displayScale) private var displayScale

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }
    private var scale: CGFloat { textSize.scale }
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

    init(
        session: UnifiedSession,
        sessionManager: SessionManager,
        physicalNotchHeight: CGFloat,
        onBack: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onShowSession: @escaping (String) -> Void = { _ in },
        keyboardInteraction: KeyboardInteractionController
    ) {
        self.session = session
        self.sessionManager = sessionManager
        self.physicalNotchHeight = physicalNotchHeight
        self.onBack = onBack
        self.onClose = onClose
        self.onShowSession = onShowSession
        self.keyboardInteraction = keyboardInteraction
    }

    var body: some View {
        VStack(spacing: 0) {
            notchTopBar

            detailHeader

            timelineContent
                .animation(.easeOut(duration: 0.16), value: hasInterruption)
        }
        .onAppear { loadTimelineAsync() }
        .onChange(of: session.currentInterruption?.id) { _, _ in
            advanceAfterNotchResolutionIfReady()
        }
        .onReceive(keyboardInteraction.commands) { event in
            guard keyboardInteraction.context == .sessionDetail,
                case .peekTools(let held) = event.command
            else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                expandTools = held
            }
        }
    }

    // MARK: - Notch top bar

    /// Keeps navigation in the physical-notch row, matching the usage page and
    /// leaving the content header's full width for session identity.
    private var notchTopBar: some View {
        HStack(spacing: 0) {
            NotchBackButton(accessibilityLabel: L("Back to list"), action: onBack)
            Spacer()
        }
        .frame(height: physicalNotchHeight + 4)
    }

    // MARK: - Interruption bar

    /// Bottom-pinned bar carrying anything that needs a response: approvals and
    /// questions.
    ///
    /// # Why it is not modal
    /// What you need in order to decide what to approve is the log itself —
    /// what was happening just before — so covering that context with a sheet or
    /// alert is counterproductive. `NotchPanel` is also nonactivating and cannot
    /// become the key window, which sheets do not tolerate well. The requirement
    /// is **non-modal but pinned**.
    ///
    /// # Why the bottom
    /// Decisions belong at the bottom, following the button placement of sheets
    /// and alerts. The timeline is bottom-anchored, so **the log immediately
    /// preceding the approval request sits directly above the bar** — context
    /// and decision adjacent.
    ///
    /// # Depth
    /// **The bar itself is transparent**; the material, corner radius,
    /// semantic-colored border, and shadow all belong to the banner card. The
    /// goal is a second surface placed inside the notch panel, and giving the
    /// bar its own surface would double it up. The log behind shows through
    /// outside the card.
    @ViewBuilder
    private var interruptionBar: some View {
        if let interruption = session.currentInterruption {
            Group {
                switch interruption {
                case .permission(let permission):
                    PermissionBanner(
                        permission: permission,
                        keyboardInteraction: keyboardInteraction,
                        onApprove: {
                            resolveInNotch(interruption, fallback: .close) {
                                permissionActions.approve(session.id, permission.toolUseId)
                            }
                        },
                        onDeny: {
                            resolveInNotch(interruption, fallback: .close) {
                                permissionActions.deny(
                                    session.id, permission.toolUseId, "Denied via Agent Notch")
                            }
                        },
                        onRespondInTerminal: session.agentType == .codex
                            && canJumpToTerminal
                            ? {
                                let navigation = interruptionNavigation.leaveForTerminal()
                                permissionActions.respondInTerminal(session.id, permission.toolUseId)
                                TerminalJumper.jump(pid: session.pid, tty: session.tty)
                                performNavigation(navigation)
                            }
                            : nil,
                        onDismiss: {
                            resolveInNotch(interruption, fallback: .close) {
                                permissionActions.dismissExpired(
                                    session.id, permission.toolUseId)
                            }
                        }
                    )
                    .glassEffectTransition(.identity)
                    .id(interruption.id)

                case .question(let question):
                    QuestionBanner(
                        questions: question.questions,
                        expiresAt: question.expiresAt,
                        isExpired: question.isExpired,
                        isSubmitting: question.isSubmitting,
                        responseMode: question.responseMode,
                        keyboardInteraction: keyboardInteraction,
                        onAnswer: { answers in
                            resolveInNotch(interruption, fallback: .back) {
                                permissionActions.answerQuestion(
                                    session.id, question.toolUseId, answers)
                            }
                        },
                        onRespondInTerminal:
                            question.responseMode == .terminalOnly && canJumpToTerminal
                            ? {
                                let navigation = interruptionNavigation.leaveForTerminal()
                                TerminalJumper.jump(pid: session.pid, tty: session.tty)
                                performNavigation(navigation)
                            }
                            : nil,
                        onDismiss: {
                            resolveInNotch(interruption, fallback: .back) {
                                permissionActions.dismissExpired(
                                    session.id, question.toolUseId)
                            }
                        }
                    )
                    .glassEffectTransition(.identity)
                    // A newly arrived request cannot replace this card. The ID
                    // changes only after the current response is resolved.
                    .id(interruption.id)
                }
            }
            // The gap between the card and the panel edge. To read as a
            // floating surface it must sit inside the header's horizontal
            // inset (20); any tighter and it looks glued to the panel.
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    /// Whether anything needs a response. Drives the bar's in/out animation.
    private var hasInterruption: Bool {
        session.currentInterruption != nil
    }

    /// Fixed session identity above the independent chat viewport.
    ///
    /// The one-device-pixel hairline is the actual boundary between the two
    /// regions; the log ends there rather than continuing underneath a header
    /// material.
    private var detailHeader: some View {
        header
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DSColors.lineDefault)
                    .frame(height: 1 / max(displayScale, 1))
                    .allowsHitTesting(false)
            }
    }

    /// The header.
    ///
    /// State glyph + two lines of identity (repo/branch/pid, then
    /// cwd/model/tok/cost) + the tools peek hint + primary destination. Only the
    /// glyph on the left speaks to state; back navigation lives in the notch
    /// row above.
    private var header: some View {
        HStack(spacing: DSSpacing.sm) {
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

            toolsPeekHint

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

            actionMenu
        }
    }

    private var codexAppJumpButton: some View {
        Button {
            SessionDestinationJumper.jump(to: session)
        } label: {
            appDestinationLabel(
                icon: CodexAppJumper.applicationIcon(for: session),
                fallbackMark: .codex,
                title: L("Codex App")
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(L("Open in Codex App"))
        .accessibilityLabel(L("Open in Codex App"))
    }

    private var claudeAppJumpButton: some View {
        Button {
            SessionDestinationJumper.jump(to: session)
        } label: {
            appDestinationLabel(
                icon: ClaudeDesktopJumper.applicationIcon(for: session),
                fallbackMark: .claudeCode,
                title: L("Claude App")
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(L("Open in Claude App"))
        .accessibilityLabel(L("Open in Claude App"))
    }

    /// An app destination reads as its own icon next to its name, the way the terminal jump does.
    /// The vendor mark is only a fallback for when Launch Services has no icon to give.
    private func appDestinationLabel(
        icon: NSImage?,
        fallbackMark: AgentType,
        title: String
    ) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: s(14), height: s(14))
            } else {
                AgentMark(
                    agentType: fallbackMark,
                    size: s(14),
                    color: DSColors.inkDim
                )
            }
            Text(title)
                .font(DSTypography.Native.caption(scale, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .contentShape(Rectangle())
    }

    private var terminalJumpButton: some View {
        Button {
            SessionDestinationJumper.jump(to: session)
        } label: {
            HStack(spacing: 5) {
                if let icon = session.terminalAppIcon as? NSImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: s(14), height: s(14))
                }
                Text(l10n: "Terminal")
                    .font(DSTypography.Native.caption(scale, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(L("Jump to terminal"))
        .accessibilityLabel(L("Jump to terminal"))
    }

    /// Line one: repo · branch · pid.
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
                Text(verbatim: L("Plan").uppercased())
                    .font(DSTypography.mono(s(8), weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(DSColors.signalPlan)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        DSShape.rounded(DSShape.tag)
                            .stroke(DSColors.signalPlan.opacity(0.5), lineWidth: 0.5)
                    )
            }
        }
    }

    /// Line two: cwd · agent · model · tokens · cost. Machine values, so mono.
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
        if tokens > 0 { parts.append(L("\(TokenFormatter.format(tokens)) TOK")) }
        if session.estimatedCost > 0 { parts.append(CostCalculator.formatCost(session.estimatedCost)) }
        if session.presence == .restored { parts.append(L("Last seen")) }
        if session.presence == .inactive { parts.append(L("Process ended")) }
        return parts.joined(separator: " · ")
    }

    /// Legend for the tools peek — a label, never a control.
    ///
    /// Chat and tools share one timeline, and tools are collapsed to a single
    /// line by default. Opening them all is a *look*, not a state you leave
    /// behind: hold Control and the whole log turns verbose, release it and it
    /// returns. A button for that would leave the log in verbose mode until you
    /// remembered to press it again, and it took the header width that session
    /// identity needs. Only the legend remains, and only while the keyboard is
    /// engaged — the hold cannot be discovered any other way, and it does not
    /// work at all before the panel takes key focus.
    @ViewBuilder
    private var toolsPeekHint: some View {
        if keyboardInteraction.isEngaged {
            KeyHintLabel(chord: .controlKey, label: L("Tools").uppercased())
                .opacity(expandTools ? 1 : 0.65)
                .animation(.easeInOut(duration: 0.15), value: expandTools)
                .accessibilityLabel(L("Hold Control to expand tool contents"))
        }
    }

    // MARK: - Action menu

    private var actionMenu: some View {
        let userState = sessionManager.userState(for: session.id)
        let isUserDone = sessionManager.isUserDone(session)
        return SessionActionMenu(
            userState: userState,
            isUserDone: isUserDone,
            hasSessionTitle: SessionCardPresentation.hasSessionTitle(session),
            showTerminalJump: canJumpToCodexApp && canJumpToTerminal,
            onTogglePin: { sessionManager.setPinned(session.id, !userState.pinned) },
            onToggleMute: { sessionManager.setMuted(session.id, !userState.muted) },
            onToggleDone: {
                isUserDone ? sessionManager.unmarkDone(session.id) : sessionManager.markDone(session.id)
            },
            onSelectTitleDisplayPreference: {
                sessionManager.setTitleDisplayPreference(session.id, $0)
            },
            onJumpToTerminal: {
                TerminalJumper.jump(pid: session.pid, tty: session.tty)
            },
            onRemove: {
                sessionManager.removeSession(id: session.id)
                sessionManager.notifyChange()
                onBack()
            },
            labelSize: s(10)
        )
    }

    // MARK: - Tasks / Subagents / Team (collapsible sections)

    private var hasWorkContext: Bool {
        !session.tasks.isEmpty || !session.subagents.isEmpty || session.teamName != nil
    }

    /// The three kinds of work context, in the order they are shown.
    private enum WorkContextKind: Hashable {
        case tasks
        case subagents
        case team

        var title: String {
            switch self {
            case .tasks: L("Tasks").uppercased()
            case .subagents: L("Subagents").uppercased()
            case .team: L("Team").uppercased()
            }
        }
    }

    /// Tasks, subagents, and team membership describe the current work state,
    /// not chronological activity, so their controls float at the chat's
    /// top-left instead of occupying header space or becoming timeline rows.
    ///
    /// # The chip *is* the panel
    /// Pressing a chip does not reveal a second surface below it — the chip's
    /// own surface grows, downward by exactly the height of its list and
    /// sideways into the free width of the row, and the list appears inside it.
    /// There is only ever one surface, so nothing about "which card belongs to
    /// which chip" has to be explained, and the label the pointer just pressed
    /// stays on the same pixels: padding and alignment do not change with
    /// state, so pressing again closes it without moving the pointer.
    ///
    /// # One at a time
    /// Two open sections would have to split the row's width between them,
    /// leaving two narrow columns of wrapped text. Opening one closes the
    /// other.
    @ViewBuilder
    private var collapsibleSections: some View {
        if hasWorkContext {
            HStack(alignment: .top, spacing: 6) {
                if !session.tasks.isEmpty {
                    let completed = session.tasks.filter { $0.status == .completed }.count
                    workContextChip(
                        kind: .tasks,
                        count: session.tasks.count,
                        countLabel: "\(completed)/\(session.tasks.count)"
                    )
                }
                if !session.subagents.isEmpty {
                    workContextChip(kind: .subagents, count: session.subagents.count)
                }
                if let team = session.teamName {
                    workContextChip(
                        kind: .team,
                        count: sessionManager.teamSessions(name: team).count
                    )
                }
                // The open chip is the one that absorbs the free width. Without
                // one, this spacer keeps the row left-aligned; with one, a
                // spacer would halve the width it grows into.
                if expandedWorkContext == nil {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expandedWorkContext)
        }
    }

    private func workContextChip(
        kind: WorkContextKind,
        count: Int,
        countLabel: String? = nil
    ) -> some View {
        let isExpanded = expandedWorkContext == kind
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedWorkContext = isExpanded ? nil : kind
                }
            } label: {
                workContextChipLabel(
                    title: kind.title,
                    count: count,
                    countLabel: countLabel,
                    isExpanded: isExpanded
                )
                .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(kind.title), \(count) items"))
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded ? L("Expanded") : L("Collapsed"))

            if isExpanded {
                expandedWorkContextList(kind)
                    .padding(.top, 8)
                    .padding(.bottom, 3)
            }
        }
        // Identical in both states, so the label does not shift when the
        // surface around it grows.
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
        // The same fill as the header's Terminal button, so a chip reads as one
        // of the panel's controls. No border: three outlined boxes in a row
        // drew more attention than the log they annotate.
        .background(DSSurfaceFill(.control))
        // Clipping the whole cell — not just its background — is what makes the
        // list look like it is being swallowed as the surface contracts.
        .clipShape(DSShape.rounded(isExpanded ? DSShape.inset : DSShape.subtle))
    }

    /// The open chip's list, scrolling within the chip once it outgrows its
    /// share of the panel.
    ///
    /// A twenty-task plan would otherwise push the log off the screen it is
    /// annotating. `ScrollView` takes whatever height it is offered, so the
    /// content is measured and the chip asks for exactly that height until it
    /// reaches the cap — below the cap there is no scrolling at all, and the
    /// surface still grows by the height of its list.
    @ViewBuilder
    private func expandedWorkContextList(_ kind: WorkContextKind) -> some View {
        ScrollView {
            workContextContent(kind)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { height in
                    workContextHeights[kind] = height
                }
        }
        .frame(height: min(workContextHeights[kind] ?? 0, s(Self.workContextMaxHeight)))
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func workContextContent(_ kind: WorkContextKind) -> some View {
        switch kind {
        case .tasks:
            TaskListSection(tasks: session.tasks, fontScale: scale)
        case .subagents:
            SubagentListView(subagents: session.subagents, fontScale: scale)
        case .team:
            if let team = session.teamName {
                TeamSection(
                    currentSessionId: session.id,
                    members: sessionManager.teamSessions(name: team),
                    fontScale: scale,
                    onShowSession: onShowSession
                )
            }
        }
    }

    private func workContextChipLabel(
        title: String,
        count: Int,
        countLabel: String?,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 8)
            Text(title)
                .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(countLabel ?? String(format: "%02d", min(count, 99)))
                .font(DSTypography.Native.monoCaption2(scale, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Timeline

    /// The chat viewport and its fixed response controls.
    ///
    /// The session header is a sibling above this view, so the log cannot pass
    /// behind it. Work-context controls float over the chat's top-left without
    /// taking height from the viewport.
    private var timelineContent: some View {
        invertedTimeline
            .overlay {
                if timeline.isEmpty && isLoading && showsSpinner {
                    timelineSpinner
                }
            }
            .overlay(alignment: .topLeading) {
                collapsibleSections
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                interruptionBar
            }
            .task {
                try? await Task.sleep(for: .milliseconds(Int(Self.spinnerDelay * 1000)))
                showsSpinner = true
            }
            .onReceive(sessionManager.objectWillChange) {
                loadTimelineAsync()
            }
    }

    /// A lazy newest-first stack, double-inverted to read chronologically.
    ///
    /// Newest is the scroll view's logical origin, so opening and following do
    /// not require SwiftUI to estimate the height of unrealized Markdown and
    /// tool rows. Only the viewport and rows are transformed; the header and
    /// response controls stay outside the transformed tree so pointer hit
    /// testing remains aligned with their presentation.
    private var invertedTimeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if let tool = session.currentTool, tool.status == .running {
                    ActiveToolIndicator(tool: tool)
                        .id("activeTool")
                        .modifier(InvertedTimelineRow())
                }

                // Newest first. Consecutive calls to the same tool collapse
                // into one row: BASH BASH BASH → BASH ×3.
                ForEach(TimelineRow.rows(from: timeline).reversed()) { row in
                    Group {
                        switch row {
                        case .message(let entry):
                            ChatMessageView(entry: entry, agentType: session.agentType)
                        case .toolRun(let entries):
                            ToolLogRow(entries: entries, expandAll: expandTools)
                        }
                    }
                    .id(row.id)
                    .modifier(InvertedTimelineRow())
                }
            }
            // Matches the horizontal inset of the header and the other
            // sections. Anything that reaches a row's right edge — such as a
            // timestamp — looks glued to the panel border with a narrower inset.
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .scrollPosition($scrollPosition)
        .modifier(ScrollNewestTracker(isAtNewest: $isAtNewest))
        // A transformed indicator would move opposite to the visible log.
        .scrollIndicators(.hidden)
        .scaleEffect(x: 1, y: -1, anchor: .center)
        // Applied after the viewport transform, so the control remains upright
        // and in the ordinary hit-test coordinate system.
        .overlay(alignment: .bottom) {
            if !isAtNewest {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { scrollToNewest() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                // Liquid Glass, since this button floats above the log: the
                // rows behind show through, so you can tell what it is
                // covering. No shadow — the glass carries its own, and `shadow`
                // would render it offscreen and bake in its translucency.
                .buttonStyle(.glass)
                .glassEffectTransition(.identity)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel(L("Scroll to the latest message"))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isAtNewest)
    }

    /// Restores a row's visual orientation inside the inverted viewport.
    private struct InvertedTimelineRow: ViewModifier {
        func body(content: Content) -> some View {
            content.scaleEffect(x: 1, y: -1, anchor: .center)
        }
    }

    // MARK: - Navigation

    /// Marks a notch-owned response before invoking its transport. Synchronous transports remove
    /// the item immediately; Codex keeps it in `.submitting` until the server confirms resolution.
    private func resolveInNotch(
        _ interruption: PendingInterruption,
        fallback: InterruptionNavigationState.Fallback,
        action: () -> Void
    ) {
        guard
            interruptionNavigation.beginResolution(
                of: interruption.id,
                fallback: fallback
            )
        else {
            return
        }
        action()
        advanceAfterNotchResolutionIfReady()
    }

    /// Advances one global FIFO only after a notch-owned response actually left the queue.
    /// Explicit terminal handoff never enters this path: it closes the panel and leaves the
    /// unresolved item to the owning terminal.
    private func advanceAfterNotchResolutionIfReady() {
        let navigation = interruptionNavigation.navigationAfterQueueChange(
            queuedInterruptions: session.pendingInterruptions.items,
            nextSessionId: sessionManager.nextPendingInterruptionSession()?.id,
            currentSessionId: session.id
        )
        if let navigation {
            performNavigation(navigation)
        }
    }

    private func performNavigation(_ navigation: InterruptionNavigationState.Navigation) {
        switch navigation {
        case .showSession(let id): onShowSession(id)
        case .close: onClose()
        case .back: onBack()
        }
    }

    // MARK: - Data Loading

    /// Fingerprint of the loaded transcript. It is not re-read unless this
    /// changes.
    private struct TranscriptSignature: Equatable {
        let size: Int
        let modified: Date?

        init(path: String) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            size = attributes?[.size] as? Int ?? 0
            modified = attributes?[.modificationDate] as? Date
        }
    }

    /// Reads the transcript and assembles the timeline. Heavy I/O, so it runs
    /// off-MainActor.
    ///
    /// # Why the fingerprint
    /// This is called on every `sessionManager.objectWillChange` — that is,
    /// whenever anything happens to the session, which is twice per tool
    /// (PreToolUse and PostToolUse). Ten tool calls would mean twenty-two
    /// re-reads, each producing the same rows, and every assignment to
    /// `timeline` rebuilds the whole timeline. On a screen where each row owns a
    /// material, those rebuilds pile up and get expensive.
    ///
    /// Nothing is read while the file's size and modification time are
    /// unchanged. A stat takes a few microseconds — orders of magnitude below
    /// parsing plus the rebuild.
    ///
    /// # Why the fingerprint is claimed before the read
    /// The whole file is parsed, so a read is not always cheap: measured on
    /// real transcripts it ranges from 41ms (0.5MB) to 1210ms (a 43MB Codex
    /// rollout). Comparing the fingerprint *inside* the read left it unclaimed
    /// for that entire window, so every notification arriving meanwhile started
    /// another full parse of the same bytes, and each one that finished
    /// reassigned `timeline` and rebuilt every row. The log never got to stay
    /// on screen long enough to be realized — which is why the sessions that
    /// opened blank were exactly the ones with the slowest reads. Stat first,
    /// claim it, then read; and never read twice at once.
    private func loadTimelineAsync() {
        guard let path = session.transcriptPath else {
            isLoading = false
            return
        }
        guard !isReadingTranscript else { return }
        let signature = TranscriptSignature(path: path)
        guard loadedSignature != signature else {
            isLoading = false
            return
        }

        isReadingTranscript = true
        loadedSignature = signature
        Task { @MainActor in
            let entries = await Task.detached {
                TranscriptReader.readTimeline(path: path, tail: 60)
            }.value

            let shouldFollowNewest = isAtNewest
            isReadingTranscript = false
            isLoading = false
            timeline = entries
            if shouldFollowNewest {
                scrollPosition.scrollTo(edge: .top)
            }
        }
    }

    /// The loading ring.
    ///
    /// `ProgressView` is drawn in the system control color, which all but sinks
    /// into black against the dark ground over glass. This uses the same **ring
    /// spinner from the glyph dictionary** as the usage gauge and picks its own
    /// color. It is `TimelineView`-driven for the same reason as `UsageGauge`:
    /// an implicit animation with repeatForever has its phase reset whenever the
    /// body is re-evaluated.
    private var timelineSpinner: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase =
                context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.1) / 1.1
            GlyphView(
                bitmap: Glyph.ringSpinner(
                    phase: phase,
                    lit: DSColors.ink.opacity(0.75),
                    track: DSColors.inkGhost
                ),
                dot: 2,
                gap: 1
            )
        }
        .accessibilityLabel(L("Loading"))
    }

    /// Jumps to the newest message.
    ///
    /// The inverted newest-first stack puts newest at the logical top edge. An
    /// edge command remains valid before the lazy stack realizes a target row.
    private func scrollToNewest() {
        scrollPosition.scrollTo(edge: .top)
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "" }
        return (path as NSString).lastPathComponent
    }
}
