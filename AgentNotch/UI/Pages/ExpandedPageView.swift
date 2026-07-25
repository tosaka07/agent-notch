import AgentNotchCore
import Defaults
import SwiftUI

/// `expanded` モードの UI。アクティブセッション一覧。
///
/// # レイアウト
/// - ヘッダ行は設けない。ソート・設定アイコンは notch 右翼、使用量ゲージ（`UsageGauge`）は
///   notch 左翼に配置し、カードを即座に表示してスクロール量を最小化する。
///   使用量ゲージは Claude / Codex を横並びで出し（取得できた方だけ）、クリックすると
///   notch 全体が使用量詳細ページ（`UsagePageView`）に切り替わる。ゲージの表示形式
///   （リング / 数字 / リング+数字）は設定から選ぶ（issue #36）。
struct ExpandedPageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var usageCoordinator: UsageCoordinator

    @Default(.textSize) private var textSize
    @Default(.sessionSortOrder) private var sortOrder
    @Default(.sessionGrouping) private var grouping
    @Default(.collapsedGroupIDs) private var collapsedGroupIDs
    @Default(.usageEnabled) private var usageEnabled

    @State private var showSortMenu = false

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// トップバー左翼に横並びで出すゲージの一覧。Claude → Codex の順。
    ///
    /// 初回ポーリングが返る前（`snapshot == nil`）は percent を nil にしたプレースホルダを出す。
    /// 何も出さないと起動直後に「ゲージが無い」ように見えて違和感があるため。
    /// 一覧はどの agentType のセッションが並ぶか一定しないため、特定セッションには紐づけない。
    private var headerUsages: [(agentType: AgentType, percent: Double?)] {
        guard usageEnabled else { return [] }
        guard let snapshot = usageCoordinator.snapshot else {
            return [(AgentType.claudeCode, nil)]
        }
        return [AgentType.claudeCode, .codex].compactMap { agentType in
            snapshot.primaryUsedPercent(for: agentType).map { (agentType, Double?.some($0)) }
        }
    }

    var body: some View {
        let groups = sessionManager.groupedSessions(order: sortOrder, grouping: grouping)
        let totalCount = groups.reduce(0) { $0 + $1.sessions.count }

        return VStack(spacing: 0) {
            // Notch 領域: 右翼にコントロールを配置
            notchTopBar(totalCount: totalCount)

            if totalCount == 0 {
                Spacer()
                Text("NO ACTIVE SESSIONS")
                    .font(DSTypography.mono(s(10), weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(DSColors.inkMute)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Notch top bar (replaces header)

    /// 物理 notch の高さ分のスペースを取りつつ、左翼に使用量ゲージ、右翼にソート・設定
    /// アイコンを配置する。compact モードの「左翼 = DotMatrix / 右翼 = PixelCounter」という
    /// 対称構造を、展開時のトップバーでも踏襲する。
    private func notchTopBar(totalCount: Int) -> some View {
        HStack(spacing: 0) {
            // 左翼: 使用量ゲージ。Claude / Codex を横並びにし、クリックで使用量詳細ページへ。
            // 表示形式（リング / 数字 / リング+数字）は設定で選ぶ（`Defaults[.usageGaugeStyle]`）。
            if !headerUsages.isEmpty {
                Button {
                    viewModel.showUsage()
                } label: {
                    HStack(spacing: 6) {
                        ForEach(headerUsages, id: \.agentType) { usage in
                            UsageGauge(usedPercent: usage.percent, agentType: usage.agentType)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("使用量の詳細を開く")
                .help("使用量の詳細を表示")
                .padding(.leading, 16)
            }

            Spacer()

            // 右翼: sort + clear + settings
            HStack(spacing: 6) {
                sortButton

                if totalCount > 0 {
                    iconButton(systemName: "xmark") {
                        sessionManager.removeAllSessions()
                        sessionManager.notifyChange()
                    }
                }
                iconButton(systemName: "gearshape") {
                    SettingsWindowController.shared.show()
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: viewModel.physicalNotchHeight + 4)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSColors.inkDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort popover

    private var sortButton: some View {
        Button { showSortMenu.toggle() } label: {
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
            Text("SORT BY")
                .font(DSTypography.mono(10, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(DSColors.inkDim)
            ForEach(SessionSortOrder.allCases, id: \.self) { order in
                selectableRow(isSelected: sortOrder == order, label: order.label) {
                    sortOrder = order
                }
            }

            Divider().padding(.vertical, 2)

            Text("GROUP BY")
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
            }
        } else {
            let isCollapsed = collapsedGroupIDs.contains(group.key)
            VStack(spacing: 4) {
                groupHeader(group, isCollapsed: isCollapsed)
                if !isCollapsed {
                    ForEach(group.sessions) { session in
                        sessionCardRow(session)
                    }
                }
            }
        }
    }

    /// `.team` グルーピングのときのみ、teammate カード（リーダー以外）に左 2px rail + 10px インデントを付ける。
    /// 他のグルーピングではネストしない。
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
                }
            )
        )
    }
}
