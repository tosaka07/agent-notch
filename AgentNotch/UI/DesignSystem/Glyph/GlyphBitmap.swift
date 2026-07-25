import SwiftUI

/// 任意サイズのドットグリフのビットマップ。
///
/// `DotBitmap` が 13×13 固定なのに対し、こちらは 3×3（usage ブロック）/ 5×5（task, subagent）/
/// 5×7（数字）/ 13×13（状態）など**サイズの違うグリフを 1 つの型で扱う**ための器。
///
/// # 唯一の絶対制約
/// ドットは点滅・移動しても必ず格子上に留まり、**サブピクセル移動をしない**。
/// アニメーションは「どのマスが光るか」の変化だけで表現し、座標を小数で動かさない。
struct GlyphBitmap: Equatable {
    let rows: Int
    let cols: Int
    /// `rows` × `cols` のセル。行優先。
    let cells: [[DotCell]]

    init(rows: Int, cols: Int, cells: [[DotCell]]) {
        self.rows = rows
        self.cols = cols
        self.cells = cells
    }

    /// `fn(x, y)` が真のマスを `on` 色、偽を `off` 色で塗った正方グリフ。
    static func square(
        _ size: Int,
        on: Color,
        off: Color? = nil,
        _ fn: (Int, Int) -> Bool
    ) -> GlyphBitmap {
        grid(rows: size, cols: size, on: on, off: off, fn)
    }

    static func grid(
        rows: Int,
        cols: Int,
        on: Color,
        off: Color? = nil,
        _ fn: (Int, Int) -> Bool
    ) -> GlyphBitmap {
        var cells: [[DotCell]] = []
        for y in 0..<rows {
            var row: [DotCell] = []
            for x in 0..<cols {
                if fn(x, y) {
                    row.append(.on(color: on))
                } else if let off {
                    row.append(.on(color: off))
                } else {
                    row.append(.off)
                }
            }
            cells.append(row)
        }
        return GlyphBitmap(rows: rows, cols: cols, cells: cells)
    }

    static func empty(rows: Int, cols: Int) -> GlyphBitmap {
        GlyphBitmap(
            rows: rows,
            cols: cols,
            cells: Array(repeating: Array(repeating: DotCell.off, count: cols), count: rows)
        )
    }

    func cell(row: Int, col: Int) -> DotCell {
        guard row >= 0, row < cells.count, col >= 0, col < cells[row].count else { return .off }
        return cells[row][col]
    }
}

/// `GlyphBitmap` を描く View。
///
/// ドット 1 個の辺を `dot`、間隔を `gap` で指定する（既定 2px / 1px = ピッチ 3px）。
/// `DotMatrix` / `PixelCounter` が使う `PixelGrid` はピッチ + 充填率のモデルだが、
/// グリフ側は「2px の点を 1px 空けて置く」という設計そのままの指定にしている。
struct GlyphView: View {
    let bitmap: GlyphBitmap
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// 未点灯セル（`DotCell.off`）を薄く見せる色。`.clear` にすると完全に消える。
    var ghost: Color = .clear

    private var width: CGFloat { CGFloat(bitmap.cols) * dot + CGFloat(max(0, bitmap.cols - 1)) * gap }
    private var height: CGFloat { CGFloat(bitmap.rows) * dot + CGFloat(max(0, bitmap.rows - 1)) * gap }

    var body: some View {
        Canvas { ctx, _ in
            let pitch = dot + gap
            for row in 0..<bitmap.rows {
                for col in 0..<bitmap.cols {
                    let cell = bitmap.cell(row: row, col: col)
                    let color: Color
                    if cell.on {
                        color = cell.color ?? DSColors.ink
                    } else if ghost != .clear {
                        color = ghost
                    } else {
                        continue
                    }
                    let rect = CGRect(
                        x: CGFloat(col) * pitch,
                        y: CGFloat(row) * pitch,
                        width: dot,
                        height: dot
                    )
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: width, height: height)
    }
}
