import AgentNotchCore
import SwiftUI

struct SessionCardView: View {
    let session: UnifiedSession
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Status + Agent name + Duration
            HStack(spacing: 6) {
                StatusIndicator(status: session.status, size: 7)
                Text(session.agentType.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.bottom, 3)

            // Row 2: Model + Path (always visible)
            HStack(spacing: 0) {
                if let model = session.model {
                    Text(shortModel(model))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("  ")
                }
                Text(projectName(session.cwd))
                    .foregroundStyle(.white.opacity(0.2))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .font(.system(size: 9, design: .monospaced))
            .padding(.bottom, 5)

            // Row 3: Tool activity (fixed height — prevents layout jump)
            HStack(spacing: 4) {
                if let tool = session.currentTool {
                    Circle()
                        .fill(session.status.color)
                        .frame(width: 4, height: 4)
                    Text(tool.name)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(session.status.color.opacity(0.8))
                    Text(tool.summary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                } else {
                    Text(session.status.label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                }
                Spacer()
            }
            .frame(height: 14) // Fixed height prevents layout jump
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(session.status == .permissionWaiting
                    ? session.status.color.opacity(0.4)
                    : Color.white.opacity(0.04), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func shortModel(_ model: String) -> String {
        // "claude-opus-4-6" → "opus-4" , "claude-sonnet-4-6" → "sonnet-4"
        let parts = model.split(separator: "-")
        if parts.count >= 3, parts.first == "claude" {
            return "\(parts[1])-\(parts[2])"
        }
        return model
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "" }
        return (path as NSString).lastPathComponent
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%d:%02d", m, s)
    }
}
