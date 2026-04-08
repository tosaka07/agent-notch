import AgentNotchCore
import Defaults
import SwiftUI

struct ToolHistoryView: View {
    let session: UnifiedSession

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        let tools = session.recentTools
        if tools.isEmpty {
            Spacer()
            Text("No tool executions yet")
                .font(.system(size: s(11)))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { _, tool in
                        ToolHistoryRow(tool: tool)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct ToolHistoryRow: View {
    let tool: ToolInfo
    @State private var isExpanded = false

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 6) {
                // Status icon
                Image(systemName: statusIcon)
                    .font(.system(size: s(8)))
                    .foregroundStyle(statusColor)
                    .frame(width: 12)

                // Tool name
                Text(tool.name)
                    .font(.system(size: s(9), weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))

                // Summary
                Text(tool.summary)
                    .font(.system(size: s(9), design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)

                Spacer()

                // Duration
                if let ms = tool.durationMs {
                    Text(formatDuration(ms))
                        .font(.system(size: s(8), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                } else if let completed = tool.completedAt {
                    let ms = Int(completed.timeIntervalSince(tool.startedAt) * 1000)
                    Text(formatDuration(ms))
                        .font(.system(size: s(8), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }

                // Time
                Text(formatTime(tool.startedAt))
                    .font(.system(size: s(8), design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }

            // Expanded detail
            if isExpanded {
                ToolDetailSection(tool: tool)
                    .padding(.leading, 24)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            }
        }
        .background(isExpanded ? Color.white.opacity(0.03) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var statusIcon: String {
        switch tool.status {
        case .running: "circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .denied: "hand.raised.fill"
        }
    }

    private var statusColor: Color {
        switch tool.status {
        case .running: .blue
        case .succeeded: .green.opacity(0.6)
        case .failed: .red.opacity(0.7)
        case .denied: .orange.opacity(0.7)
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let s = Double(ms) / 1000.0
        if s < 60 { return String(format: "%.1fs", s) }
        return String(format: "%dm%ds", Int(s) / 60, Int(s) % 60)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

private struct ToolDetailSection: View {
    let tool: ToolInfo

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show input details based on tool type
            switch tool.name {
            case "Bash":
                if let cmd = tool.input["command"], !cmd.isEmpty {
                    DetailBlock(label: "command", content: cmd)
                }
            case "Edit":
                if let path = tool.input["file_path"] {
                    DetailBlock(label: "file", content: path)
                }
                if let old = tool.input["old_string"], !old.isEmpty {
                    DetailBlock(label: "old", content: old, color: .red.opacity(0.4))
                }
                if let new = tool.input["new_string"], !new.isEmpty {
                    DetailBlock(label: "new", content: new, color: .green.opacity(0.4))
                }
            case "Write":
                if let path = tool.input["file_path"] {
                    DetailBlock(label: "file", content: path)
                }
            case "Read":
                if let path = tool.input["file_path"] {
                    DetailBlock(label: "file", content: path)
                }
            case "Grep", "Glob":
                if let pattern = tool.input["pattern"] {
                    DetailBlock(label: "pattern", content: pattern)
                }
            default:
                // Generic: show all inputs
                ForEach(Array(tool.input.prefix(4)), id: \.key) { key, value in
                    DetailBlock(label: key, content: value)
                }
            }
        }
    }
}

private struct DetailBlock: View {
    let label: String
    let content: String
    var color: Color = .white.opacity(0.05)

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: s(8), weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            Text(content.prefix(500))
                .font(.system(size: s(9), design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(8)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
