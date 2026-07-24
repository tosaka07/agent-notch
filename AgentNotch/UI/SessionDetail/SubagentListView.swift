import AgentNotchCore
import SwiftUI

/// SUBAGENTS セクションの中身。実行中（経過時間、1s 更新）を上に、完了（所要時間）を新しい順に並べる。
/// 完了 5 件超は折りたたむ。
struct SubagentListView: View {
    let subagents: [SubagentRun]
    var fontSize: CGFloat = 9

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
                    Text("+\(completed.count - 5) more")
                        .font(DSTypography.mono(fontSize))
                        .foregroundStyle(DSColors.inkMute)
                }
            }
        }
    }

    private func row(glyph: String, color: Color, agentType: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(glyph)
                .foregroundStyle(color)
            Text(agentType)
                .foregroundStyle(DSColors.inkDim)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .foregroundStyle(DSColors.inkMute)
        }
        .font(DSTypography.mono(fontSize))
    }

    private func elapsed(_ start: Date, at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }

    private func duration(_ start: Date, _ end: Date?) -> String {
        guard let end else { return "—" }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }
}
