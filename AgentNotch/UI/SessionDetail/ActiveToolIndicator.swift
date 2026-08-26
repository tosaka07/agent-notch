import AgentNotchCore
import Defaults
import SwiftUI

/// The "currently running tool" row at the end of the timeline.
///
/// It takes **the same header-row shape** as a finished tool (`ToolLogRow`) so
/// nothing jumps the moment it completes. The differences are the pulsing dot
/// and the elapsed seconds ticking up.
struct ActiveToolIndicator: View {
    let tool: ToolInfo

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TimelineMetrics.spacing) {
            // The marker column is simply left empty. The dot marks messages
            // only; that this is running is said by the tool name's color and
            // the elapsed seconds growing at the right edge.
            Color.clear.frame(width: TimelineMetrics.marker, height: 1)

            Text(tool.name.uppercased())
                .foregroundStyle(DSColors.signalAlert)

            Text(tool.summary)
                .foregroundStyle(DSColors.inkMute)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            TimelineView(.periodic(from: tool.startedAt, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(tool.startedAt)
                Text(formatElapsed(elapsed))
                    .foregroundStyle(DSColors.signalAlert.opacity(0.8))
            }
        }
        .font(DSTypography.mono(s(9)))
        .tracking(0.8)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Running: \(tool.name), \(tool.summary)"))
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return L("\(seconds)s") }
        return L("\(seconds / 60)m\(seconds % 60)s")
    }
}

#Preview("Active Tool Indicator") {
    ActiveToolIndicator(
        tool: ToolInfo(
            id: "1",
            name: "Bash",
            summary: "swift build",
            input: ["command": "swift build"],
            startedAt: .now.addingTimeInterval(-8),
            status: .running
        )
    )
    .padding(16)
    .frame(width: 420)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
