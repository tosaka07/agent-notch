import AgentNotchCore
import SwiftUI

/// Contents of the TEAM section: the member list, where tapping a row opens
/// that teammate's detail, plus a task board of assigned tasks.
struct TeamSection: View {
    let currentSessionId: String
    let members: [UnifiedSession]
    /// `Defaults[.textSize].scale`, used as the base scale for
    /// DSTypography.Native.
    var fontScale: CGFloat = 1
    var onShowSession: (String) -> Void = { _ in }

    /// The leader (teammateName == nil) first, then the rest in start order.
    private var sortedMembers: [UnifiedSession] {
        members.sorted { lhs, rhs in
            if (lhs.teammateName == nil) != (rhs.teammateName == nil) {
                return lhs.teammateName == nil
            }
            return lhs.startedAt < rhs.startedAt
        }
    }

    /// A board aggregating every member's tasks that have an assignee.
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
        let memberName = member.teammateName ?? L("Lead")
        return Button {
            onShowSession(member.id)
        } label: {
            HStack(spacing: 6) {
                StatusIndicator(status: member.status, size: 7 * fontScale)
                Text(memberName.uppercased())
                    .font(
                        DSTypography.Native.monoFootnote(
                            fontScale, weight: member.id == currentSessionId ? .semibold : .regular)
                    )
                    .foregroundStyle(member.id == currentSessionId ? Color.primary : Color.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(member.id == currentSessionId)
        .accessibilityLabel(
            member.id == currentSessionId
                ? L("\(memberName) (current session)")
                : memberName
        )
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 6) {
            // Drawn as a dot glyph rather than font characters (□▪■).
            GlyphView(bitmap: Glyph.task(task.glyph, color: task.glyphColor))
            Text(task.subject)
                .foregroundStyle(
                    task.status == .completed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
                )
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
