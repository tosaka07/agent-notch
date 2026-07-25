import Defaults
import SwiftUI

/// 使用率を表す小さな常時表示ゲージ（リング or 数字）。タップで表示形式を切り替えられる。
///
/// `ExpandedPageView`（セッション一覧）のトップバー左翼に常設する想定。ここは compact モードの
/// `DotMatrix` と同じ「notch の翼」そのものの位置であり、パネル内部（#37 の Native 化対象）とは
/// 違って独自のピクセル言語を保つ場所のため、標準 SwiftUI の `Circle`/`Text` ではなく
/// `PixelGrid` + `DotCell`（compact 側と共通の描画基盤）で描く。
///
/// - リング: 13×13 グリッド上に円環状に並んだ28ドット（`ringPoints`。中心 (6,6) 半径6の
///   Bresenham circle を12時位置から時計回りに並べたもの）を使用率に応じて先頭から点灯させる。
///   未点灯のドットも `Color.secondary.opacity(0.25)` で薄く残し、常に円の形が読めるようにする
///   （座標自体は Bresenham circle アルゴリズムで一度だけ生成し、compact 側の cross/exclamation
///   と同様に決め打ちの座標配列として持つ）。
/// - 数字: `PixelCounter.drawTwoDigit` の 5×4 digit bitmap をそのまま再利用し、2桁を
///   13×13 グリッドの中央（rowOffset 4）に描く。100% は 99 に丸める（2桁までしか描けないため）。
///
/// 70%/90% で `DSColors.signalAlert`/`signalError` にエスカレーションする点、タップで
/// `Defaults[.usageGaugeStyle]` を切り替える点は維持。Reduce Motion 時はリング⇔数字の
/// 切り替えクロスフェードを止める（ドット自体は Canvas 即時描画のためアニメーション対象にしない）。
struct UsageGauge: View {
    /// 0〜100 の使用率。
    let usedPercent: Double
    /// グリッド全体の一辺のサイズ。compact 左翼の `DotMatrix`（cellSize 1.6 → 13×1.6≈21pt）に揃える。
    var size: CGFloat = 21

    @Default(.usageGaugeStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    private var color: Color {
        switch clampedPercent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: .secondary
        }
    }

    private var cellSize: CGFloat { size / CGFloat(PixelGrid.dimension) }

    var body: some View {
        Button {
            style = style.toggled
        } label: {
            Group {
                switch style {
                case .ring:
                    PixelGrid(cells: ringCells, cellSize: cellSize)
                case .number:
                    PixelGrid(cells: numberCells, cellSize: cellSize)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: style)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("使用率")
        .accessibilityValue("\(Int(clampedPercent.rounded()))パーセント")
        .accessibilityHint("タップで表示形式を切り替え")
        .help("使用率 \(Int(clampedPercent.rounded()))%（タップで表示切替）")
    }

    // MARK: - Ring

    /// 中心 (6,6) 半径6の Bresenham circle を12時位置（真上）から時計回りに並べた28点。
    private static let ringPoints: [(row: Int, col: Int)] = [
        (0, 6), (1, 7), (1, 8), (2, 9), (3, 10), (4, 11), (5, 11), (6, 12),
        (7, 11), (8, 11), (9, 10), (10, 9), (11, 8), (11, 7), (12, 6), (11, 5),
        (11, 4), (10, 3), (9, 2), (8, 1), (7, 1), (6, 0), (5, 1), (4, 1),
        (3, 2), (2, 3), (1, 4), (1, 5),
    ]

    private var ringCells: [[DotCell]] {
        var cells = DotBitmap.emptyCellGrid()
        let litCount = Int((clampedPercent / 100 * Double(Self.ringPoints.count)).rounded())
        for (index, point) in Self.ringPoints.enumerated() {
            let dotColor = index < litCount ? color : Color.secondary.opacity(0.25)
            cells[point.row][point.col] = .on(color: dotColor)
        }
        return cells
    }

    // MARK: - Number

    private var numberCells: [[DotCell]] {
        var cells = DotBitmap.emptyCellGrid()
        // 2桁までしか描けないため 100% は 99 に丸める。
        let value = min(99, Int(clampedPercent.rounded()))
        PixelCounter.drawTwoDigit(value, rowOffset: 4, color: color, into: &cells)
        return cells
    }
}

#Preview("Usage Gauge") {
    HStack(spacing: 24) {
        VStack(spacing: 6) {
            UsageGauge(usedPercent: 12, size: 28)
            Text("12%").font(.caption2)
        }
        VStack(spacing: 6) {
            UsageGauge(usedPercent: 78, size: 28)
            Text("78%").font(.caption2)
        }
        VStack(spacing: 6) {
            UsageGauge(usedPercent: 95, size: 28)
            Text("95%").font(.caption2)
        }
    }
    .padding(24)
    .background(Color.black)
}
