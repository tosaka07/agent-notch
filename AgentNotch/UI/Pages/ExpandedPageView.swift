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
///   （リング / 数字）は設定から選ぶ（issue #36）。
struct ExpandedPageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var usageCoordinator: UsageCoordinator

    @Default(.textSize) private var textSize
    @Default(.sessionSortOrder) private var sortOrder
    @Default(.sessionGrouping) private var grouping
    @Default(.collapsedGroupIDs) private var collapsedGroupIDs
    @Default(.usageEnabled) private var usageEnabled
    @Default(.usageGaugeMetric) private var usageGaugeMetric
    @Environment(\.permissionActions) private var permissionActions

    @State private var showSortMenu = false

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// トップバー左翼に横並びで出すゲージの一覧。Claude → Codex の順。
    ///
    /// 初回ポーリングが返る前（`snapshot == nil`）は percent を nil にしたプレースホルダを出す。
    /// 何も出さないと起動直後に「ゲージが無い」ように見えて違和感があるため
    /// （`UsageGauge` 側が nil をローディングのスピナーとして描く）。
    /// 一覧はどの agentType のセッションが並ぶか一定しないため、特定セッションには紐づけない。
    ///
    /// どの枠（セッション / ウィークリー / …）を出すかは設定 `usageGaugeMetric` に従う。
    private var headerUsages: [HeaderUsage] {
        guard usageEnabled else { return [] }
        guard let snapshot = usageCoordinator.snapshot else {
            return [HeaderUsage(agentType: .claudeCode, percent: nil, isUnavailable: false)]
        }
        let resolved = [AgentType.claudeCode, .codex].compactMap { agentType in
            snapshot.primaryWindow(for: agentType, metric: usageGaugeMetric).map {
                HeaderUsage(agentType: agentType, percent: $0.usedPercent, isUnavailable: false)
            }
        }
        guard resolved.isEmpty else { return resolved }
        // 1 つも取得できなかった場合も、使用量ページ（取得できない理由が出る）への
        // 導線を残すため「取得なし」のゲージを 1 つだけ置く。
        return [HeaderUsage(agentType: .claudeCode, percent: nil, isUnavailable: true)]
    }

    private struct HeaderUsage: Identifiable {
        let agentType: AgentType
        let percent: Double?
        /// 取得を試みたが値が無い（従量課金・資格情報なし・取得失敗）。
        let isUnavailable: Bool

        var id: AgentType { agentType }
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
    /// アイコンを配置する。compact モードの「左翼 = 状態グリフ / 右翼 = PixelCounter」という
    /// 対称構造を、展開時のトップバーでも踏襲する。
    private func notchTopBar(totalCount: Int) -> some View {
        HStack(spacing: 0) {
            // 左翼: 使用量ゲージ。Claude / Codex を横並びにし、クリックで使用量詳細ページへ。
            // 表示形式（リング / 数字）は設定で選ぶ（`Defaults[.usageGaugeStyle]`）。
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
                .accessibilityLabel("使用量の詳細を開く")
                .help("使用量の詳細を表示")
                // 右翼のアイコンは 28pt のタップ領域の中央に描かれるので、絵柄の左端は
                // パネル端から 16 + 7.5 ≒ 24pt の位置に来る。ゲージはグリフそのもので
                // 内側余白を持たないため、同じ 24 を直接与えて絵柄の位置を左右で揃える。
                .padding(.leading, 24)
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

    /// 使用量バッジ。エージェント 1 つにつきグリフ 1 個だけを置く（モック 1b）。
    ///
    /// 設定が `.ring` ならリング、`.number` なら数字グリフ。**併記しない**——
    /// リングは残量を形で語り切っているので % テキストは同じ情報の二重表示になり、
    /// 「リングを選んだのに数字も出る」状態になる。どのエージェントかはグリフの色相で分かる
    /// （`UsageGauge` の通常域の色 = `AgentType.color`）ので、名前テキストも置かない。
    /// 正確な値と内訳は、このバッジをクリックして開く使用量ページ側の責務。
    private func usageBadge(_ usage: HeaderUsage) -> some View {
        let value = usage.percent.map { "\(Int($0.rounded()))%" }
            ?? (usage.isUnavailable ? "取得できません" : "取得中")
        let frame = usageGaugeMetric == .auto || usage.isUnavailable
            ? ""
            : " · \(usageGaugeMetric.label)"
        return UsageGauge(
            usedPercent: usage.percent,
            agentType: usage.agentType,
            isUnavailable: usage.isUnavailable
        )
        .help("\(usage.agentType.displayName)\(frame): \(value)")
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
                },
                // 一覧から直接承認/拒否する（誤タップガードはカード側の armedAfter）。
                approve: { toolUseId in
                    permissionActions.approve(session.id, toolUseId)
                },
                deny: { toolUseId in
                    permissionActions.deny(session.id, toolUseId, "Denied via Agent Notch")
                }
            )
        )
    }
}
