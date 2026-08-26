import AgentNotchCore
import Defaults
import SwiftUI

struct ToolHistoryView: View {
    let session: UnifiedSession

    @Default(.textSize) private var textSize
    private var scale: CGFloat { textSize.scale }

    var body: some View {
        let tools = session.recentTools
        if tools.isEmpty {
            Spacer()
            Text(l10n: "No tool executions yet")
                .font(DSTypography.Native.callout(scale))
                .foregroundStyle(.tertiary)
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

#Preview("Tool History") {
    let session = UnifiedSession(id: "1", agentType: .claudeCode)
    session.recentTools = [
        ToolInfo(
            id: "1", name: "Edit", summary: "SessionDetailView.swift",
            input: [
                "file_path": "SessionDetailView.swift", "old_string": "Color.white.opacity(0.08)",
                "new_string": "Divider()",
            ],
            startedAt: .now.addingTimeInterval(-30), completedAt: .now.addingTimeInterval(-29),
            status: .succeeded, durationMs: 800),
        ToolInfo(
            id: "2", name: "Bash", summary: "swift build",
            input: ["command": "swift build"],
            startedAt: .now.addingTimeInterval(-10), status: .running),
    ]
    return ToolHistoryView(session: session)
        .frame(width: 320, height: 240)
        .background(Color.black)
}

private struct ToolHistoryRow: View {
    let tool: ToolInfo
    @State private var isExpanded = false

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scale: CGFloat { textSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 6) {
                // Status icon
                Image(systemName: statusIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor)
                    .frame(width: 12)

                // Tool name
                Text(tool.name)
                    .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                    .foregroundStyle(.primary)

                // Summary
                Text(tool.summary)
                    .font(DSTypography.Native.monoCaption(scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Duration
                if let ms = tool.durationMs {
                    Text(formatDuration(ms))
                        .font(DSTypography.Native.monoCaption2(scale))
                        .foregroundStyle(.tertiary)
                } else if let completed = tool.completedAt {
                    let ms = Int(completed.timeIntervalSince(tool.startedAt) * 1000)
                    Text(formatDuration(ms))
                        .font(DSTypography.Native.monoCaption2(scale))
                        .foregroundStyle(.tertiary)
                }

                // Time
                Text(formatTime(tool.startedAt))
                    .font(DSTypography.Native.monoCaption2(scale))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isExpanded.toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded ? L("Expanded") : L("Collapsed"))

            // Expanded detail
            if isExpanded {
                ToolDetailSection(tool: tool)
                    .padding(.leading, 24)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            }
        }
        // The expanded contents are a surface for showing values; while
        // collapsed there is no surface at all.
        .background { if isExpanded { DSSurfaceFill(.inset) } }
        .clipShape(DSShape.rounded(DSShape.subtle))
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
        case .running: DSColors.signalWorking
        case .succeeded: DSColors.signalDone
        case .failed: DSColors.signalError
        case .denied: DSColors.signalAlert
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return L("\(ms)ms") }
        let s = Double(ms) / 1000.0
        if s < 60 { return L("\(String(format: "%.1f", s))s") }
        return L("\(Int(s) / 60)m\(Int(s) % 60)s")
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
    private var scale: CGFloat { textSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show input details based on tool type
            switch tool.name {
            case "Bash":
                if let cmd = tool.input["command"], !cmd.isEmpty {
                    DetailBlock(label: L("command"), content: cmd)
                }
            case "Edit":
                if let path = tool.input["file_path"] {
                    DetailBlock(label: L("file"), content: path)
                }
                if let old = tool.input["old_string"], !old.isEmpty {
                    DetailBlock(label: L("old"), content: old, tint: .red)
                }
                if let new = tool.input["new_string"], !new.isEmpty {
                    DetailBlock(label: L("new"), content: new, tint: .green)
                }
            case "Write":
                if let path = tool.input["file_path"] {
                    DetailBlock(label: L("file"), content: path)
                }
            case "Read":
                if let path = tool.input["file_path"] {
                    DetailBlock(label: L("file"), content: path)
                }
            case "Grep", "Glob":
                if let pattern = tool.input["pattern"] {
                    DetailBlock(label: L("pattern"), content: pattern)
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
    /// Tint for diff display (old/new). A neutral material background when nil.
    var tint: Color?

    @Default(.textSize) private var textSize
    private var scale: CGFloat { textSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DSTypography.Native.caption2(scale, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(content.prefix(500))
                .font(DSTypography.Native.monoCaption(scale))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(8)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if let tint {
                        DSShape.rounded(DSShape.badge).fill(tint.opacity(0.15))
                    } else {
                        DSShape.rounded(DSShape.badge).fill(.quaternary)
                    }
                }
        }
    }
}
