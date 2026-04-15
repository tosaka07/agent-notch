import AgentNotchCore
import Defaults
import SwiftUI

/// `expanded` モードの UI。アクティブセッション一覧 + 操作バー（sort / clear all / settings）。
struct ExpandedPageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager

    @Default(.textSize) private var textSize
    @Default(.sessionSortOrder) private var sortOrder
    @Default(.sessionGrouping) private var grouping
    @Default(.collapsedGroupIDs) private var collapsedGroupIDs

    @State private var showSortMenu = false

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        // groupedSessions() は O(n log n)。body 評価ごとに複数回走らせないよう、
        // ここで一度だけ計算してローカルに保持する。
        let groups = sessionManager.groupedSessions(order: sortOrder, grouping: grouping)
        let totalCount = groups.reduce(0) { $0 + $1.sessions.count }

        return VStack(spacing: 0) {
            Spacer().frame(height: viewModel.physicalNotchHeight + 4)

            header(totalCount: totalCount)

            if totalCount == 0 {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: s(11)))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Header

    private func header(totalCount: Int) -> some View {
        HStack(spacing: 6) {
            Text("Sessions")
                .font(.system(size: s(12), weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))

            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.system(size: s(9), weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            sortButton

            if totalCount > 0 {
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
    }

    private var sortButton: some View {
        Button {
            showSortMenu.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: s(11)))
                .foregroundStyle(.white.opacity(0.3))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSortMenu, arrowEdge: .top) {
            sortPopoverContent
                .padding(10)
                .frame(width: 180)
        }
    }

    private var sortPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("並び替え")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(SessionSortOrder.allCases, id: \.self) { order in
                selectableRow(isSelected: sortOrder == order, label: order.label) {
                    sortOrder = order
                }
            }

            Divider().padding(.vertical, 2)

            Text("グループ化")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(SessionGrouping.allCases, id: \.self) { group in
                selectableRow(isSelected: grouping == group, label: group.label) {
                    grouping = group
                }
            }
        }
    }

    private func selectableRow(isSelected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark" : "")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                Text(label)
                    .font(.system(size: 12))
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
            // フラット表示
            ForEach(group.sessions) { session in
                sessionCard(session)
            }
        } else {
            let isCollapsed = collapsedGroupIDs.contains(group.key)
            VStack(spacing: 6) {
                groupHeader(group, isCollapsed: isCollapsed)
                if !isCollapsed {
                    ForEach(group.sessions) { session in
                        sessionCard(session)
                    }
                }
            }
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
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: s(9), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 10)
                Text(group.title)
                    .font(.system(size: s(10), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(group.sessions.count)")
                    .font(.system(size: s(9), weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
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
                togglePin: { sessionManager.setPinned(session.id, !userState.pinned) },
                toggleMute: { sessionManager.setMuted(session.id, !userState.muted) },
                toggleDone: {
                    isUserDone
                        ? sessionManager.unmarkDone(session.id)
                        : sessionManager.markDone(session.id)
                }
            )
        )
    }
}
