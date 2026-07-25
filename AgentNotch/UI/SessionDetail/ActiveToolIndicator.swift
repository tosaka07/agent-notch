import AgentNotchCore
import Defaults
import SwiftUI

/// タイムライン末尾に出す「いま走っているツール」の行。
///
/// 完了したツール（`ToolLogRow`）と**同じヘッダー行の形**にして、終わった瞬間に
/// 見た目が飛ばないようにする。違いはドットが脈動していることと、経過秒が伸びていくこと。
struct ActiveToolIndicator: View {
    let tool: ToolInfo

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // ToolLogRow の chevron と同じ幅を空けてドットの位置を縦に揃える。
            Color.clear.frame(width: 8, height: 1)

            PulsingDot(color: DSColors.signalAlert, size: 6)

            Text(Self.timeFormatter.string(from: tool.startedAt))
                .foregroundStyle(DSColors.inkMute)

            Text(tool.name.uppercased())
                .foregroundStyle(DSColors.ink.opacity(0.7))

            Text(tool.summary)
                .foregroundStyle(DSColors.inkMute)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

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
    .frame(width: 420)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
