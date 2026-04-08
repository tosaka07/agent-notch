import AgentNotchCore
import Defaults
import SwiftUI

struct ActiveToolIndicator: View {
    let tool: ToolInfo

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange.opacity(0.5))
                .frame(width: 2)

            HStack(spacing: 6) {
                PulsingDot(color: .blue, size: 5)

                Text(tool.name)
                    .font(.system(size: s(9), weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.8))

                Text(tool.summary)
                    .font(.system(size: s(9), design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)

                Spacer()

                TimelineView(.periodic(from: tool.startedAt, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(tool.startedAt)
                    Text(formatElapsed(elapsed))
                        .font(.system(size: s(8), weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }
}
