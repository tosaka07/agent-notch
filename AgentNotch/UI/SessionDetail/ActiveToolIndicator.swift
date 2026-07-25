import AgentNotchCore
import Defaults
import SwiftUI

struct ActiveToolIndicator: View {
    let tool: ToolInfo

    @Default(.textSize) private var textSize
    private var scale: CGFloat { textSize.scale }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange.opacity(0.5))
                .frame(width: 2)

            HStack(spacing: 6) {
                PulsingDot(color: DSColors.signalWorking, size: 5)

                Text(tool.name)
                    .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                Text(tool.summary)
                    .font(DSTypography.Native.monoCaption(scale))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                TimelineView(.periodic(from: tool.startedAt, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(tool.startedAt)
                    Text(formatElapsed(elapsed))
                        .font(DSTypography.Native.monoCaption2(scale, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("実行中: \(tool.name), \(tool.summary)")
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }
}

#Preview("Active Tool Indicator") {
    ActiveToolIndicator(tool: ToolInfo(
        id: "1",
        name: "Bash",
        summary: "swift build",
        input: ["command": "swift build"],
        startedAt: .now.addingTimeInterval(-8),
        status: .running
    ))
    .padding(16)
    .frame(width: 320)
    .background(Color.black)
}
