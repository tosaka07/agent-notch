import SwiftUI

/// 日毎の値を縦棒で表す bar chart。棒はドットを積み上げて描く。
///
/// `PixelBar` が横方向の 1 本のメーターなのに対し、こちらは複数の縦棒を並べる。
/// notch の翼と同じ独自言語側の表現なので、標準の Swift Charts ではなくドットで描く
/// （`DotMatrix` / `PixelCounter` / `PixelBar` と同じ Canvas + dotFillRatio の流儀）。
///
/// 値が 0 の日も**必ず 1 段だけ薄いドットを置く**ので、休んだ日が「棒が無い」ではなく
/// 「底だけある」と読めて、日付軸の連続性が崩れない。
struct PixelBarChart: View {
    /// 左から古い順の値。空なら何も描かない。
    let values: [Double]
    /// 棒の色。しきい値で色を変えたい場合は呼び出し側で値ごとに `barColors` を渡す。
    var color: Color = DSColors.ink
    /// 値ごとの色（`values` と同じ長さ）。指定した場合 `color` より優先。
    var barColors: [Color]? = nil
    /// 縦のドット段数。
    var rows: Int = 12
    /// 1 dot を配置するマスのサイズ。
    var cellSize: CGFloat = 5
    /// dot 直径 / cell サイズ。
    var dotFillRatio: CGFloat = 0.75
    /// 棒と棒の間に空けるマス数。
    var columnGap: Int = 1

    private var maxValue: Double { max(values.max() ?? 0, .leastNonzeroMagnitude) }

    var body: some View {
        Canvas { ctx, canvasSize in
            guard !values.isEmpty else { return }
            let dotSize = cellSize * dotFillRatio
            let dotInset = (cellSize - dotSize) / 2
            let columnStride = CGFloat(1 + columnGap) * cellSize
            let usedWidth = columnStride * CGFloat(values.count) - CGFloat(columnGap) * cellSize
            // 右端（最新日）を右揃えにする。入り切らない場合は古い方から溢れる。
            let offsetX = max(0, canvasSize.width - usedWidth)
            let offsetY = (canvasSize.height - CGFloat(rows) * cellSize) / 2

            for (index, value) in values.enumerated() {
                let normalized = min(max(value / maxValue, 0), 1)
                // 値があるなら最低 1 段は光らせる（微小な日が「無い」ように見えないように）。
                let litRows = value > 0 ? max(1, Int((normalized * Double(rows)).rounded())) : 0
                let barColor = barColors?[safe: index] ?? color
                let x = offsetX + CGFloat(index) * columnStride + dotInset

                for row in 0..<rows {
                    // 下から積む。
                    let isLit = row >= rows - litRows
                    let isBaseline = row == rows - 1
                    guard isLit || isBaseline else { continue }
                    let rect = CGRect(
                        x: x,
                        y: offsetY + CGFloat(row) * cellSize + dotInset,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.fill(
                        Path(rect),
                        with: .color(isLit ? barColor : DSColors.inkGhost)
                    )
                }
            }
        }
        .frame(height: CGFloat(rows) * cellSize)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Pixel Bar Chart") {
    let values: [Double] = [0, 12, 48, 3, 96, 61, 0, 24, 88, 100, 7, 55, 33, 0]
    return VStack(alignment: .leading, spacing: 16) {
        PixelBarChart(values: values)
        PixelBarChart(
            values: values,
            barColors: values.map { $0 >= 90 ? DSColors.signalError : ($0 >= 60 ? DSColors.signalAlert : DSColors.ink) }
        )
    }
    .padding(20)
    .frame(width: 420)
    .background(Color.black)
}
