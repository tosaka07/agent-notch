import SwiftUI

/// 1 dot の状態。描画するか（`on`）と色を 1 つの値に集約する。
///
/// グラデーションや agent 種別ごとの色分けは、`DotCell` の 2D 配列を組み立てる側で
/// 事前に色を決めて `.on(color:)` を渡すことで実現する。
struct DotCell: Hashable, Sendable {
    let on: Bool
    /// nil のときは `PixelGrid.color` の default を使う。
    let color: Color?

    static let off = DotCell(on: false, color: nil)

    /// `.on()` = default color、`.on(color: .red)` = 指定色
    static func on(color: Color? = nil) -> DotCell {
        DotCell(on: true, color: color)
    }
}

/// 15×15 の `DotCell` 二次元配列を Canvas で描画する共通 atom。
///
/// DotMatrix と PixelCounter の両方が内部でこれを使う。
/// これにより「左翼と右翼の粒サイズ・粒間・描画手法が完全に一致」する。
///
/// # 設計
/// - View 自体はフレームサイズを固定せず、**親のサイズに fit する**
/// - Canvas 内で 15×15 grid を受け取ったサイズの**中央に配置して描画**
/// - on cell = `cell.color ?? color`、off cell = `ghostColor` で薄く描画
/// - padding は親（wing 全体など）側で規定する
struct PixelGrid: View {
    /// `[rows][cols]` の 15×15 cell 配列。足りない部分は off 扱い。
    let cells: [[DotCell]]
    /// 1 dot を配置するマス（cell）のサイズ。grid 全体は `cellSize × dimension` の正方形。
    var cellSize: CGFloat = 1.6
    /// dot 1 個の辺のサイズ / cell サイズの比率。1.0 で密着、< 1 で cell 内に gap。
    /// 例: `dotFillRatio = 0.75` → dot は cell 中央に 75% の大きさで描画、25% が gap。
    var dotFillRatio: CGFloat = 0.75
    /// `cell.color` が nil のときに使われる default 色。
    var color: Color = DSColors.ink
    /// off dot の色（薄く grid を見せる）。透明にしたい場合は `.clear` を渡す。
    var ghostColor: Color = DSColors.inkGhost
    /// on dot 側にのみ掛ける opacity（breathing アニメーション等）。ghost には影響しない。
    var opacity: Double = 1.0

    /// 1 辺の cell 数（= dot 数）。
    static let dimension = 15

    var body: some View {
        Canvas { ctx, canvasSize in
            let gridSize = cellSize * CGFloat(Self.dimension)
            let offsetX = (canvasSize.width - gridSize) / 2
            let offsetY = (canvasSize.height - gridSize) / 2
            let dotSize = cellSize * dotFillRatio
            let dotInset = (cellSize - dotSize) / 2

            for r in 0..<Self.dimension {
                for c in 0..<Self.dimension {
                    let cell = cellAt(row: r, col: c)
                    let x = offsetX + CGFloat(c) * cellSize + dotInset
                    let y = offsetY + CGFloat(r) * cellSize + dotInset
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)

                    let dotColor: Color
                    if cell.on {
                        dotColor = (cell.color ?? color).opacity(opacity)
                    } else {
                        dotColor = ghostColor
                    }
                    ctx.fill(Path(rect), with: .color(dotColor))
                }
            }
        }
    }

    private func cellAt(row: Int, col: Int) -> DotCell {
        guard row < cells.count, col < cells[row].count else { return .off }
        return cells[row][col]
    }
}

// MARK: - Bitmap → Cells helpers

extension Array where Element == [Bool] {
    /// `[[Bool]]` bitmap を `[[DotCell]]` に変換する。on cell は default color を使う（nil）。
    /// 色を個別に塗りたい場合は呼び出し側で map を重ねる。
    func toCells() -> [[DotCell]] {
        map { row in row.map { $0 ? .on() : .off } }
    }

    /// on cell を指定色で塗った `[[DotCell]]` に変換する。
    func toCells(onColor: Color) -> [[DotCell]] {
        map { row in row.map { $0 ? .on(color: onColor) : .off } }
    }
}
