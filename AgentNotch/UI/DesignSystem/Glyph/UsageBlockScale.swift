import SwiftUI

/// 使用量の目盛り（Claude Design モック 2b / 3b）。
///
/// グリフ辞書の D（3×3 ブロック）を 10 個並べて 100% を表す。**1 ブロック = 10%**。
/// 連続的なバーではなく離散的なブロックにするのは、
/// - 「あと何ブロック残っているか」が数として読める
/// - **severity は色だけを変え、目盛りは変えない**ので、API 由来の severity と
///   自前のしきい値が同じ目盛りに乗る
/// という 2 点のため。
struct UsageBlockScale: View {
    /// 0〜100 の使用率。
    let usedPercent: Double
    /// 消費済みブロックの色。severity で変えるのは色だけ。
    var color: Color = DSColors.ink
    /// ブロック数。10 個 = 100%（1 個 10%）。
    var blocks: Int = 10
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// ブロック間の間隔。
    var spacing: CGFloat = 5

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<blocks, id: \.self) { index in
                GlyphView(
                    bitmap: Glyph.usageBlock(
                        filled: Double(index) / Double(blocks) < clampedPercent / 100 - 0.001,
                        color: color
                    ),
                    dot: dot,
                    gap: gap
                )
            }
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(clampedPercent.rounded()))パーセント")
    }
}

/// 日毎コストの棒グラフ（モック 3b）。
///
/// 1 列 = 1 日。3×3 ブロックを**下から積み上げて**高さで量を表す。
/// 値があれば最低 1 ブロックは点灯させるので、少額の日が「無い」ように見えない。
/// 最新の列だけ色を強めて「今日」が分かるようにする。
struct UsageBlockChart: View {
    /// 左から古い順の値。
    let values: [Double]
    /// 1 列あたりの最大ブロック数。
    var blocksPerColumn: Int = 6
    var color: Color = DSColors.ink.opacity(0.62)
    var latestColor: Color = DSColors.ink
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    var columnSpacing: CGFloat = 2

    private var maxValue: Double { max(values.max() ?? 0, .leastNonzeroMagnitude) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                column(value: value, isLatest: index == values.count - 1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func column(value: Double, isLatest: Bool) -> some View {
        let ratio = value / maxValue
        // 値があるなら最低 1 ブロックは光らせる（微小な日が「無い」ように見えないように）。
        let lit = value > 0 ? max(1, Int((ratio * Double(blocksPerColumn)).rounded())) : 0
        return VStack(spacing: columnSpacing) {
            // 上から描くので、点灯は下側（index が大きい方）に寄せる。
            ForEach(0..<blocksPerColumn, id: \.self) { index in
                GlyphView(
                    bitmap: Glyph.usageBlock(
                        filled: index >= blocksPerColumn - lit,
                        color: isLatest ? latestColor : color
                    ),
                    dot: dot,
                    gap: gap
                )
            }
        }
    }
}

#Preview("Usage Block Scale / Chart") {
    VStack(alignment: .leading, spacing: 22) {
        ForEach([12.0, 48.0, 62.0, 88.0, 100.0], id: \.self) { percent in
            HStack(spacing: 12) {
                UsageBlockScale(
                    usedPercent: percent,
                    color: percent >= 90
                        ? DSColors.signalError
                        : (percent >= 70 ? DSColors.signalAlert : DSColors.ink)
                )
                Text("\(Int(percent))%")
                    .font(DSTypography.mono(10, weight: .semibold))
                    .foregroundStyle(DSColors.inkDim)
            }
        }

        Divider().overlay(DSColors.lineDefault)

        UsageBlockChart(
            values: [0.3, 0.5, 0.2, 0.8, 0.45, 0.6, 0.1, 0.9, 0.7, 0.35, 0.55, 1, 0.65, 0.4]
        )
        .frame(width: 360)
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
