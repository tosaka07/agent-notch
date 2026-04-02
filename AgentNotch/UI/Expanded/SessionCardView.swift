import AgentNotchCore
import SwiftUI

struct SessionCardView: View {
    let session: UnifiedSession
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusIndicator(status: session.status, size: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 8) {
                if let model = session.model {
                    Text(model)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                if let cwd = session.cwd {
                    Text(shortenPath(cwd))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }

            if let tool = session.currentTool {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8))
                    Text("\(tool.name): \(tool.summary)")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.green.opacity(0.8))
            }

            HStack(spacing: 12) {
                Label(TokenFormatter.format(session.totalInputTokens), systemImage: "arrow.down")
                Label(TokenFormatter.format(session.totalOutputTokens), systemImage: "arrow.up")
                Spacer()
                Text(CostCalculator.formatCost(session.estimatedCost))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var short = path
        if short.hasPrefix(home) {
            short = "~" + short.dropFirst(home.count)
        }
        let components = short.split(separator: "/")
        if components.count > 3 {
            return "~/" + components.suffix(2).joined(separator: "/")
        }
        return short
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%dm %02ds", m, s)
    }
}
