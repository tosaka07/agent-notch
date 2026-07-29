import SwiftUI

/// A dot-glyph bitmap of arbitrary size.
///
/// A container for **glyphs of different sizes in one type**: 3×3 (usage block),
/// 5×5 (task, subagent), 5×7 (numbers), 13×13 (state).
///
/// # The one absolute constraint
/// Dots always stay on the grid as they blink and move — **no sub-pixel movement**.
/// Animation is expressed purely as a change in which cells are lit; coordinates never
/// move by fractions.
struct GlyphBitmap: Equatable {
    let rows: Int
    let cols: Int
    /// `rows` × `cols` cells, in row-major order.
    let cells: [[DotCell]]

    /// A square glyph with cells where `fn(x, y)` is true painted `on`, and false painted `off`.
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

/// A view that draws a `GlyphBitmap`.
///
/// One dot's side is `dot` and the spacing is `gap` (defaults 2px / 1px = 3px pitch).
/// `PixelGrid`, used by `DotMatrix` / `PixelCounter`, models this as pitch + fill ratio, but
/// glyphs are specified the way they are designed: "2px dots placed 1px apart".
struct GlyphView: View {
    let bitmap: GlyphBitmap
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// Color that makes unlit cells (`DotCell.off`) faintly visible. `.clear` hides them entirely.
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
