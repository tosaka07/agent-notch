import AgentNotchCore
import SwiftUI

/// TEAM セクションの中身。メンバー一覧（行タップで teammate detail へ遷移）+ assignee 付きタスクボード。
struct TeamSection: View {
    let currentSessionId: String
    let members: [UnifiedSession]
    var fontSize: CGFloat = 9
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
                StatusIndicator(status: member.status, size: fontSize * 0.8)
                Text((member.teammateName ?? "LEAD").uppercased())
                    .font(DSTypography.mono(fontSize, weight: member.id == currentSessionId ? .semibold : .regular))
                    .foregroundStyle(member.id == currentSessionId ? DSColors.ink : DSColors.inkDim)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(member.id == currentSessionId)
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 4) {
            Text(task.status.glyph)
                .foregroundStyle(task.status.color)
            Text(task.subject)
                .foregroundStyle(task.status == .completed ? DSColors.inkMute : DSColors.inkDim)
                .lineLimit(1)
            if let assignee = task.assignee {
                Text("@\(assignee)")
                    .foregroundStyle(DSColors.inkMute)
            }
            Spacer()
        }
        .font(DSTypography.mono(fontSize))
    }
}
