import AgentNotchCore
import Defaults
import SwiftUI

/// UI for the `expanded` mode: the list of active sessions.
///
/// # Layout
/// - There is no header row. The sort, mute-all, and settings icons live in the
///   notch's right wing and the usage gauge (`UsageGauge`) in the left, so the
///   cards appear immediately and scrolling is kept to a minimum. The gauges
///   show Claude and Codex side by side — only those that could be fetched —
///   and clicking one turns the whole notch into the usage detail page
///   (`UsagePageView`). The gauge's presentation (ring or number) is chosen in
///   settings.
struct ExpandedPageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var usageCoordinator: UsageCoordinator
    let keyboardInteraction: KeyboardInteractionController

    @Default(.textSize) private var textSize
    @Default(.sessionSortOrder) private var sortOrder
    @Default(.sessionGrouping) private var grouping
    @Default(.collapsedGroupIDs) private var collapsedGroupIDs
    @Default(.usageEnabled) private var usageEnabled
    @Default(.usageGaugeMetric) private var usageGaugeMetric
    @Default(.codexIntegrationEnabled) private var codexIntegrationEnabled

    @State private var showSortMenu = false
    @State private var keyboardFocusedSessionID: String?

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// The gauges shown side by side in the top bar's left wing, Claude then
    /// Codex.
    ///
    /// Presence is decided by `UsageGaugeSurface`, which guarantees a gauge
    /// never disappears just because its fetch failed; see that type for why.
    /// Before the first poll returns the gauges appear with nil percentages,
    /// which `UsageGauge` draws as a loading spinner. They are not tied to a
    /// particular session, since which agentTypes appear in the list varies.
    ///
    /// Which window (session, weekly, …) is displayed follows the
    /// `usageGaugeMetric` setting.
    private var headerUsages: [UsageGaugeSurface.Item] {
        guard usageEnabled else { return [] }
        return UsageGaugeSurface.items(
            snapshot: usageCoordinator.snapshot,
            metric: usageGaugeMetric,
            codexIntegrationEnabled: codexIntegrationEnabled
        )
    }

    var body: some View {
        let groups = sessionManager.groupedSessions(order: sortOrder, grouping: grouping)
        let totalCount = groups.reduce(0) { $0 + $1.sessions.count }

        return VStack(spacing: 0) {
            notchTopBar(totalCount: totalCount)

            if totalCount == 0 {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: Self.sessionCardSpacing) {
                            ForEach(groups) { group in
                                groupSection(group)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: keyboardFocusedSessionID) { _, sessionId in
                        guard keyboardInteraction.isEngaged, let sessionId else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(sessionId, anchor: .center)
                        }
                    }
                }
            }
        }
        .onChange(of: keyboardSessionIDs) { _, _ in
            validateKeyboardSelection()
        }
        .onReceive(keyboardInteraction.commands) { event in
            handleKeyboardCommand(event.command)
        }
    }

    /// Shown when there is no session at all.
    ///
    /// An empty state is not an error, so neither a warning color nor a negative
    /// figure is used. Text alone would drop back into language while every
    /// other screen speaks in dots, so a dozing-face glyph leads and the wording
    /// is only a small note beneath it.
    private var emptyState: some View {
        VStack(spacing: DSSpacing.md) {
            DozingGlyphView(height: s(60))
            Text(verbatim: L("No active sessions").uppercased())
                .font(DSTypography.mono(s(9), weight: .medium))
                .tracking(1.5)
                .foregroundStyle(DSColors.inkMute)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("No active sessions"))
    }

    // MARK: - Notch top bar (replaces header)

    /// Reserves the physical notch's height while placing the usage gauge in the
    /// left wing and the sort and settings icons in the right. The expanded top
    /// bar keeps compact mode's symmetry: state glyph on the left, PixelCounter
    /// on the right.
    private func notchTopBar(totalCount: Int) -> some View {
        HStack(spacing: 0) {
            // Left wing: the usage gauges. Claude and Codex side by side, with a
            // click opening the usage detail page. The presentation (ring or
            // number) is chosen via `Defaults[.usageGaugeStyle]`.
            if !headerUsages.isEmpty {
                Button {
                    viewModel.showUsage()
                } label: {
                    HStack(spacing: 10) {
                        ForEach(headerUsages) { usage in
                            usageBadge(usage)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Open usage details"))
                .help(L("Show usage details"))
                // The right-wing icons are drawn at the center of a 28pt tap
                // area, so their artwork starts 16 + 7.5 ≈ 24pt from the panel
                // edge. A gauge is the glyph itself and carries no inner
                // padding, so it gets the same 24 directly and the artwork
                // lines up on both sides.
                .padding(.leading, 24)
            }

            Spacer()

            // Right wing: sort + mute all + settings
            HStack(spacing: 6) {
                sortButton

                if totalCount > 0 {
                    muteAllButton
                }
                iconButton(systemName: "gearshape") {
                    SettingsWindowController.shared.show(sessionManager: sessionManager)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: viewModel.physicalNotchHeight + 4)
    }

    /// The usage badge: exactly one glyph per agent.
    ///
    /// A ring when the setting is `.ring`, a number glyph when it is `.number`
    /// — **never both**. The ring already says the remaining amount through its
    /// shape, so a % label would show the same information twice and produce
    /// "I picked the ring and got numbers anyway". Which agent it is comes from
    /// the glyph's hue (`UsageGauge`'s normal-range color = `AgentType.color`),
    /// so there is no name text either. Exact values and the breakdown belong to
    /// the usage page this badge opens.
    private func usageBadge(_ usage: UsageGaugeSurface.Item) -> some View {
        let value =
            usage.percent.map { "\(Int($0.rounded()))%" }
            ?? usage.reason?.shortLabel
            ?? L("Loading")
        let frame =
            usageGaugeMetric == .auto || usage.isUnavailable
            ? ""
            : " · \(usageGaugeMetric.label)"
        return UsageGauge(
            usedPercent: usage.percent,
            agentType: usage.agentType,
            isUnavailable: usage.isUnavailable
        )
        .help("\(usage.agentType.displayName)\(frame): \(value)")
    }

    private func iconButton(
        systemName: String,
        tint: Color = DSColors.inkDim,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A single aggregate control for the same per-session mute state exposed by
    /// each card's action menu. A mixed state reads as off; pressing it mutes
    /// every visible session, and the next press unmutes all of them.
    private var muteAllButton: some View {
        let isMuted = sessionManager.areAllActiveSessionsMuted
        return iconButton(
            systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2",
            tint: isMuted ? DSColors.ink : DSColors.inkDim
        ) {
            withAnimation(.easeOut(duration: 0.12)) {
                sessionManager.setAllActiveSessionsMuted(!isMuted)
            }
        }
        .help(isMuted ? L("Unmute all sessions") : L("Mute all sessions"))
        .accessibilityLabel(isMuted ? L("Unmute all sessions") : L("Mute all sessions"))
    }

    // MARK: - Sort popover

    private var sortButton: some View {
        Button {
            showSortMenu.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSColors.inkDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSortMenu, arrowEdge: .top) {
            sortPopoverContent
                .padding(12)
                .frame(width: 200)
        }
    }

    private var sortPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: L("Sort by").uppercased())
                .font(DSTypography.mono(10, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(DSColors.inkDim)
            ForEach(SessionSortOrder.allCases, id: \.self) { order in
                selectableRow(isSelected: sortOrder == order, label: order.label) {
                    sortOrder = order
                }
            }

            Divider().padding(.vertical, 2)

            Text(verbatim: L("Group by").uppercased())
                .font(DSTypography.mono(10, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(DSColors.inkDim)
            ForEach(SessionGrouping.allCases, id: \.self) { group in
                selectableRow(isSelected: grouping == group, label: group.label) {
                    grouping = group
                }
            }
        }
    }

    private func selectableRow(
        isSelected: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                    .foregroundStyle(isSelected ? Color.primary : Color.clear)
                Text(label.uppercased())
                    .font(DSTypography.mono(11))
                    .tracking(0.5)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group sections

    @ViewBuilder
    private func groupSection(_ group: SessionGroup) -> some View {
        if grouping == .none {
            ForEach(group.sessions) { session in
                sessionCard(session)
                    .id(session.id)
            }
        } else {
            let isCollapsed = collapsedGroupIDs.contains(group.key)
            VStack(spacing: Self.sessionCardSpacing) {
                groupHeader(group, isCollapsed: isCollapsed)
                if !isCollapsed {
                    ForEach(group.sessions) { session in
                        sessionCardRow(session)
                            .id(session.id)
                    }
                }
            }
        }
    }

    private static let sessionCardSpacing: CGFloat = 6

    /// Only under `.team` grouping do teammate cards (everyone but the leader)
    /// get a 2px rail on the left plus a 10px indent. Other groupings do not
    /// nest.
    @ViewBuilder
    private func sessionCardRow(_ session: UnifiedSession) -> some View {
        if grouping == .team, session.teammateName != nil {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DSColors.lineStrong)
                    .frame(width: 2)
                sessionCard(session)
                    .padding(.leading, 10)
            }
        } else {
            sessionCard(session)
        }
    }

    private func groupHeader(_ group: SessionGroup, isCollapsed: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if isCollapsed {
                    collapsedGroupIDs.remove(group.key)
                } else {
                    collapsedGroupIDs.insert(group.key)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: s(8), weight: .semibold))
                    .foregroundStyle(DSColors.inkDim)
                    .frame(width: 10)
                Text(group.title.uppercased())
                    .font(DSTypography.mono(s(10), weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(DSColors.inkDim)
                Text(String(format: "%02d", min(group.sessions.count, 99)))
                    .font(DSTypography.mono(s(9), weight: .medium))
                    .foregroundStyle(DSColors.inkMute)
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sessionCard(_ session: UnifiedSession) -> some View {
        let userState = sessionManager.userState(for: session.id)
        let isUserDone = sessionManager.isUserDone(session)
        return SessionCardView(
            session: session,
            userState: userState,
            isUserDone: isUserDone,
            isKeyboardFocused: keyboardInteraction.isEngaged
                && keyboardFocusedSessionID == session.id,
            actions: SessionCardActions(
                tap: { viewModel.showSession(session.id) },
                remove: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        sessionManager.removeSession(id: session.id)
                        sessionManager.notifyChange()
                    }
                },
                togglePin: {
                    sessionManager.setPinned(session.id, !userState.pinned)
                },
                toggleMute: {
                    sessionManager.setMuted(session.id, !userState.muted)
                },
                toggleDone: {
                    if isUserDone {
                        sessionManager.unmarkDone(session.id)
                    } else {
                        sessionManager.markDone(session.id)
                    }
                },
                selectTitleDisplayPreference: { preference in
                    sessionManager.setTitleDisplayPreference(session.id, preference)
                }
            )
        )
    }

    // MARK: - Keyboard navigation

    private var keyboardSessions: [UnifiedSession] {
        sessionManager.groupedSessions(order: sortOrder, grouping: grouping).flatMap {
            group -> [UnifiedSession] in
            if grouping != .none, collapsedGroupIDs.contains(group.key) {
                return []
            }
            return group.sessions
        }
    }

    private var keyboardSessionIDs: [String] {
        keyboardSessions.map(\.id)
    }

    private func validateKeyboardSelection() {
        let ids = keyboardSessionIDs
        if let keyboardFocusedSessionID, !ids.contains(keyboardFocusedSessionID) {
            self.keyboardFocusedSessionID = nil
        }
    }

    private func moveKeyboardSelection(by delta: Int) {
        let ids = keyboardSessionIDs
        guard !ids.isEmpty else { return }
        guard let focused = keyboardFocusedSessionID,
            let index = ids.firstIndex(of: focused)
        else {
            keyboardFocusedSessionID = ids.first
            return
        }
        keyboardFocusedSessionID = ids[(index + delta + ids.count) % ids.count]
    }

    private func handleKeyboardCommand(_ command: KeyboardCommand) {
        guard keyboardInteraction.isEngaged,
            keyboardInteraction.context == .expanded
        else { return }

        switch command {
        case .focusInitial:
            keyboardFocusedSessionID = nil
        case .movePrevious:
            moveKeyboardSelection(by: -1)
        case .moveNext:
            moveKeyboardSelection(by: 1)
        case .activate:
            guard let keyboardFocusedSessionID else {
                self.keyboardFocusedSessionID = keyboardSessionIDs.first
                return
            }
            viewModel.showSession(keyboardFocusedSessionID)
        case .jumpToSessionDestination:
            guard
                let session = ExpandedKeyboardTargetResolver.focusedSession(
                    focusedSessionID: keyboardFocusedSessionID,
                    sessions: keyboardSessions
                )
            else { return }
            SessionDestinationJumper.jump(to: session)
        default:
            break
        }
    }
}

enum ExpandedKeyboardTargetResolver {
    static func focusedSession(
        focusedSessionID: String?,
        sessions: [UnifiedSession]
    ) -> UnifiedSession? {
        guard let focusedSessionID,
            let session = sessions.first(where: { $0.id == focusedSessionID })
        else { return nil }
        return session
    }
}
