import SwiftUI

/// 使用率を横一列（複数行可）のドットで表す横長メーター。
///
/// `PixelGrid` が 13×13 の固定正方形なのに対し、こちらは**与えられた幅いっぱいに**
/// ドットを敷き詰める。使用量ページのように「1 行 1 ウィンドウ」で並べる場面では、
/// 幅を余らせずに使えて視認性も高い。
///
/// notch の翼と同じ独自言語側の表現なので、標準の `ProgressView` ではなくドットで描く。
/// `DotMatrix` / `PixelCounter` と同じ Canvas 描画・同じ `dotFillRatio` の流儀に揃えてある。
struct PixelBar: View {
    /// 0〜100 の使用率。
    let usedPercent: Double
    /// 使用済み部分のドット色。
    var color: Color = DSColors.ink
    /// 残り部分のドット色。
    var trackColor: Color = DSColors.inkGhost
    /// 1 dot を配置するマスのサイズ。
    var cellSize: CGFloat = 5
    /// dot 直径 / cell サイズ。`PixelGrid` の既定と揃えている。
    var dotFillRatio: CGFloat = 0.75
    /// 縦のドット数。2 行にすると細い線ではなく「帯」として読める。
    var rows: Int = 2

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    var body: some View {
        Canvas { ctx, canvasSize in
            let columns = max(1, Int(canvasSize.width / cellSize))
            let litColumns = Int((clampedPercent / 100 * Double(columns)).rounded())
            let dotSize = cellSize * dotFillRatio
            let dotInset = (cellSize - dotSize) / 2
            // 端数を左右に均等に振って、バー全体が中央に収まるようにする。
            let usedWidth = CGFloat(columns) * cellSize
            let offsetX = (canvasSize.width - usedWidth) / 2
            let offsetY = (canvasSize.height - CGFloat(rows) * cellSize) / 2

            for row in 0..<rows {
                for col in 0..<columns {
                    let rect = CGRect(
                        x: offsetX + CGFloat(col) * cellSize + dotInset,
                        y: offsetY + CGFloat(row) * cellSize + dotInset,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.fill(Path(rect), with: .color(col < litColumns ? color : trackColor))
                }
            }
        }
        .frame(height: CGFloat(rows) * cellSize)
    }
}

#Preview("Pixel Bar") {
    VStack(alignment: .leading, spacing: 14) {
        ForEach([3.0, 33.0, 72.0, 96.0], id: \.self) { percent in
            PixelBar(
                usedPercent: percent,
                color: percent >= 90
                    ? DSColors.signalError
                    : (percent >= 70 ? DSColors.signalAlert : DSColors.ink)
            )
        }
    }
    .padding(20)
    .frame(width: 420)
    .background(Color.black)
}
