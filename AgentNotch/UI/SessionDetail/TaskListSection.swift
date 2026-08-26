import AgentNotchCore
import SwiftUI

/// A compact, ordered view of the agent's current plan.
///
/// The parser owns Codex/Claude schema differences; this view only renders the
/// shared task model, so new task sources do not require another UI surface.
struct TaskListSection: View {
    let tasks: [AgentTask]
    var fontScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(tasks) { task in
                taskRow(task)
            }
        }
    }

    private func taskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 7) {
            GlyphView(bitmap: Glyph.task(task.glyph, color: task.glyphColor))

            VStack(alignment: .leading, spacing: 1) {
                Text(task.subject)
                    .foregroundStyle(
                        task.status == .completed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
                    )
                    .lineLimit(2)

                if let description = task.description,
                    description != task.subject
                {
                    Text(description)
                        .font(DSTypography.Native.monoCaption2(fontScale))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let assignee = task.assignee {
                Text("@\(assignee)")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .font(DSTypography.Native.monoFootnote(fontScale))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.subject), \(statusLabel(task.status))")
    }

    private func statusLabel(_ status: AgentTask.Status) -> String {
        switch status {
        case .pending:
            L("Pending")
        case .inProgress:
            L("In progress")
        case .completed:
            L("Completed")
        }
    }
}

#Preview("Task List") {
    TaskListSection(tasks: [
        AgentTask(id: "1", subject: "Inspect the event pipeline", status: .completed),
        AgentTask(
            id: "2",
            subject: "Normalize planning tools",
            status: .inProgress,
            description: "Normalizing planning tools"
        ),
        AgentTask(id: "3", subject: "Run regression tests"),
    ])
    .padding(16)
    .frame(width: 320)
    .background(Color.black)
}
