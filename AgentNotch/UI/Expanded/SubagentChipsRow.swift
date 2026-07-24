import AgentNotchCore
import SwiftUI

/// SessionCardView 用の subagent チップ行。◆（running）/ ◇（done）グリフで表現する。
/// task の □▪■ グリフと衝突しないよう別グリフを使う。
///
/// 実行中は経過時間付きで最大 3 チップ + `+N`、完了は `◇ N done` に集約する。
struct SubagentChipsRow: View {
    let subagents: [SubagentRun]
    var fontSize: CGFloat = 8

    private var running: [SubagentRun] {
        subagents.filter { $0.status == .running }.sorted { $0.startedAt < $1.startedAt }
    }

    private var completedCount: Int {
        subagents.filter { $0.status == .completed }.count
    }

    var body: some View {
        if !subagents.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    ForEach(running.prefix(3)) { run in
                        HStack(spacing: 3) {
                            Text("◆")
                                .foregroundStyle(DSColors.signalWorking)
                            Text(run.agentType)
                                .foregroundStyle(DSColors.inkDim)
                                .lineLimit(1)
                            Text(elapsed(since: run.startedAt, at: context.date))
                                .foregroundStyle(DSColors.inkMute)
                        }
                    }
                    if running.count > 3 {
                        Text("+\(running.count - 3)")
                            .foregroundStyle(DSColors.inkMute)
                    }
                    if completedCount > 0 {
                        HStack(spacing: 3) {
                            Text("◇")
                                .foregroundStyle(DSColors.inkMute)
                            Text("\(completedCount) done")
                                .foregroundStyle(DSColors.inkMute)
                        }
                    }
                    Spacer()
                }
                .font(DSTypography.mono(fontSize))
            }
        }
    }

    private func elapsed(since start: Date, at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }
}
