import SwiftUI

/// セッション状態を 13×13 ドットマトリクスで表現する atom。
///
/// 描画は `PixelGrid` に委譲。PixelCounter と完全に同じ描画手法で、粒サイズ・粒間が一致する。
struct DotMatrix: View {
    let pattern: DotPattern
    var cellSize: CGFloat = 1.6
    var dotFillRatio: CGFloat = 0.75
    var useSignalColor: Bool = true
    /// complete パターンの書き順アニメ開始時刻。nil なら絶対時刻を使う。
    var animationStartTime: Date?

    var body: some View {
        // パターンごとに必要な tick 間隔だけ評価する（詳細は `DotPattern.minimumTickInterval`）。
        // nil のパターン（complete / swarm）のみ毎フレーム評価する。
        if let interval = pattern.minimumTickInterval {
            TimelineView(.animation(minimumInterval: interval)) { ctx in
                gridView(date: ctx.date)
            }
        } else {
            TimelineView(.animation) { ctx in
                gridView(date: ctx.date)
            }
        }
    }

    private func gridView(date: Date) -> some View {
        let t: TimeInterval
        if let start = animationStartTime, pattern == .complete {
            t = max(0, date.timeIntervalSince(start))
        } else {
            t = date.timeIntervalSinceReferenceDate
        }
        let dotColor = useSignalColor ? pattern.signalColor : DSColors.ink
        let cells = DotBitmap.cellGrid(for: pattern, time: t, signalColor: dotColor)
        let op = pattern == .standby ? breathingOpacity(time: date.timeIntervalSinceReferenceDate) : 1.0
        return PixelGrid(
            cells: cells,
            cellSize: cellSize,
            dotFillRatio: dotFillRatio,
            opacity: op
        )
    }

    private func breathingOpacity(time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 1.4) / 1.4
        return 0.35 + sin(phase * 2 * .pi) * 0.5 * 0.65 + 0.325
    }
}

#Preview("All patterns") {
    let patterns: [DotPattern] = [
        .standby, .thinking, .working, .alert, .fault, .complete, .planReview,
        .swarm(active: 1), .swarm(active: 2), .swarm(active: 3),
        .swarm(active: 4), .swarm(active: 5), .swarm(active: 6),
        .swarm(active: 7), .swarm(active: 8), .swarm(active: 9),
    ]
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
        ForEach(patterns, id: \.self) { pattern in
            DotMatrix(pattern: pattern, cellSize: 4)
                .frame(width: 60, height: 60)
        }
    }
    .padding(24)
    .background(Color.black)
}
