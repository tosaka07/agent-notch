import SwiftUI

/// セッション状態を 15×15 ドットマトリクスで表現する atom。
///
/// 描画は `PixelGrid` に委譲。PixelCounter と完全に同じ描画手法で、粒サイズ・粒間が一致する。
///
/// # 色制御
/// - `useSignalColor = true` (デフォルト): pattern.signalColor で色が付く
/// - `false`: 白単色（通知表示中の視覚衝突回避など）
struct DotMatrix: View {
    let pattern: DotPattern
    /// 1 dot = 1 cell のサイズ。PixelCounter と同じ値にすると両翼の粒度が揃う。
    var cellSize: CGFloat = 1.6
    /// dot 直径 / cell サイズの比率。1.0 密着、< 1 で cell 内に gap。
    var dotFillRatio: CGFloat = 0.75
    var useSignalColor: Bool = true

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bitmap = DotBitmap.grid(for: pattern, time: t)
            let dotColor = useSignalColor ? pattern.signalColor : DSColors.ink
            let cells = bitmap.toCells(onColor: dotColor)
            let opacity = pattern == .standby ? breathingOpacity(time: t) : 1.0
            PixelGrid(
                cells: cells,
                cellSize: cellSize,
                dotFillRatio: dotFillRatio,
                opacity: opacity
            )
        }
    }

    /// 1.4s 周期で 0.35 ↔ 1.0 を行き来する。
    private func breathingOpacity(time: TimeInterval) -> Double {
        let period = 1.4
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let wave = sin(phase * 2 * .pi) * 0.5 + 0.5
        return 0.35 + wave * 0.65
    }
}
