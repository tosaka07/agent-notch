import AgentNotchCore
import SwiftUI

/// Contents of the SUBAGENTS section. Running entries (elapsed time, refreshed
/// every second) come first, then completed ones (total duration) newest first.
/// Anything past five completed entries is collapsed.
struct SubagentListView: View {
    let subagents: [SubagentRun]
    /// `Defaults[.textSize].scale`, used as the base scale for
    /// DSTypography.Native.
    var fontScale: CGFloat = 1

    private var running: [SubagentRun] {
        subagents.filter { $0.status == .running }.sorted { $0.startedAt < $1.startedAt }
    }

    private var completed: [SubagentRun] {
        subagents.filter { $0.status == .completed }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 3) {
                ForEach(running) { run in
                    row(
                        glyph: "◆",
                        color: DSColors.signalWorking,
                        agentType: run.agentType,
                        detail: elapsed(run.startedAt, at: context.date)
                    )
                }
                ForEach(completed.prefix(5)) { run in
                    row(
                        glyph: "◇",
                        color: DSColors.inkMute,
                        agentType: run.agentType,
                        detail: duration(run.startedAt, run.endedAt)
                    )
                }
                if completed.count > 5 {
                    Text(verbatim: L("+\(completed.count - 5) more"))
                        .font(DSTypography.Native.monoFootnote(fontScale))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func row(glyph: String, color: Color, agentType: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(glyph)
                .foregroundStyle(color)
            Text(agentType)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .foregroundStyle(.tertiary)
        }
        .font(DSTypography.Native.monoFootnote(fontScale))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agentType), \(detail)")
    }

    private func elapsed(_ start: Date, at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        if seconds < 60 { return L("\(seconds)s") }
        return L("\(seconds / 60)m\(seconds % 60)s")
    }

    private func duration(_ start: Date, _ end: Date?) -> String {
        guard let end else { return "—" }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return L("\(seconds)s") }
        return L("\(seconds / 60)m\(seconds % 60)s")
    }
}

#Preview("Subagent List") {
    SubagentListView(subagents: [
        SubagentRun(
            id: "1", agentType: "Explore", startedAt: .now.addingTimeInterval(-12), hasExplicitId: true),
        SubagentRun(
            id: "2", agentType: "code-reviewer", startedAt: .now.addingTimeInterval(-90),
            endedAt: .now.addingTimeInterval(-30), status: .completed, hasExplicitId: true),
    ])
    .padding(16)
    .frame(width: 280)
    .background(Color.black)
}
