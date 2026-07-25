import AgentNotchCore
import SwiftUI

/// TEAM セクションの中身。メンバー一覧（行タップで teammate detail へ遷移）+ assignee 付きタスクボード。
struct TeamSection: View {
    let currentSessionId: String
    let members: [UnifiedSession]
    /// `Defaults[.textSize].scale`。DSTypography.Native の基準スケールとして使う。
    var fontScale: CGFloat = 1
    var onShowSession: (String) -> Void = { _ in }

    /// リーダー（teammateName == nil）を先頭に、それ以降は開始順。
    private var sortedMembers: [UnifiedSession] {
        members.sorted { lhs, rhs in
            if (lhs.teammateName == nil) != (rhs.teammateName == nil) {
                return lhs.teammateName == nil
            }
            return lhs.startedAt < rhs.startedAt
        }
    }

    /// 各メンバーの assignee 付きタスクを集約したボード。
    private var assignedTasks: [(sessionId: String, task: AgentTask)] {
        members.flatMap { member in
            member.tasks.filter { $0.assignee != nil }.map { (member.id, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sortedMembers) { member in
                    memberRow(member)
                }
            }

            if !assignedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(assignedTasks, id: \.task.id) { entry in
                        taskRow(entry.task)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: UnifiedSession) -> some View {
        Button {
            onShowSession(member.id)
        } label: {
            HStack(spacing: 6) {
                StatusIndicator(status: member.status, size: 7 * fontScale)
                Text((member.teammateName ?? "LEAD").uppercased())
                    .font(DSTypography.Native.monoFootnote(fontScale, weight: member.id == currentSessionId ? .semibold : .regular))
                    .foregroundStyle(member.id == currentSessionId ? Color.primary : Color.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(member.id == currentSessionId)
        .accessibilityLabel((member.teammateName ?? "LEAD") + (member.id == currentSessionId ? " (現在のセッション)" : ""))
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 4) {
            Text(task.status.glyph)
                .foregroundStyle(task.status.color)
            Text(task.subject)
                .foregroundStyle(task.status == .completed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            if let assignee = task.assignee {
                Text("@\(assignee)")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(DSTypography.Native.monoFootnote(fontScale))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Team Section") {
    let lead = UnifiedSession(id: "lead", agentType: .claudeCode, status: .toolRunning)
    let member = UnifiedSession(id: "wt-a", agentType: .claudeCode, status: .idle)
    member.teammateName = "wt-answer"

    return TeamSection(
        currentSessionId: "lead",
        members: [lead, member]
    )
    .padding(16)
    .frame(width: 280)
    .background(Color.black)
}
