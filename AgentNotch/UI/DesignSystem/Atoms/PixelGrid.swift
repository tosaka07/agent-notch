import SwiftUI

/// The state of one dot: whether it is drawn (`on`) and its color, in a single value.
///
/// Gradients and per-agent coloring are done by whoever builds the 2D `DotCell` array:
/// decide the color up front and pass it through `.on(color:)`.
struct DotCell: Hashable, Sendable {
    let on: Bool
    /// When nil, `PixelGrid.color`'s default is used.
    let color: Color?

    static let off = DotCell(on: false, color: nil)

    /// `.on()` = default color, `.on(color: .red)` = explicit color.
    static func on(color: Color? = nil) -> DotCell {
        DotCell(on: true, color: color)
    }
}

/// Shared atom that renders a 15×15 2D array of `DotCell` through a Canvas.
///
/// Both DotMatrix and PixelCounter use this internally, which is what keeps the dot size,
/// dot spacing, and drawing technique identical between the left and right wings.
///
/// # Design
/// - The view does not fix its own frame size; it **fits the parent's size**
/// - Inside the Canvas, the 15×15 grid is **centered** within the size it was given
/// - on cell = `cell.color ?? color`, off cell = drawn faintly with `ghostColor`
/// - Padding is the parent's responsibility (the wing as a whole, etc.)
struct PixelGrid: View {
    /// A 15×15 `[rows][cols]` cell array. Anything missing counts as off.
    let cells: [[DotCell]]
    /// Size of the cell a dot sits in. The whole grid is a `cellSize × dimension` square.
    var cellSize: CGFloat = 1.6
    /// Ratio of one dot's side to the cell size. 1.0 touches, < 1 leaves a gap inside the cell.
    /// e.g. `dotFillRatio = 0.75` → the dot is drawn at 75% centered in the cell, 25% is gap.
    var dotFillRatio: CGFloat = 0.75
    /// Default color used when `cell.color` is nil.
    var color: Color = DSColors.ink
    /// Color of off dots (a faint visible grid). Pass `.clear` to hide them.
    var ghostColor: Color = DSColors.inkGhost
    /// Opacity applied to on dots only (breathing animation, etc.). Ghosts are unaffected.
    var opacity: Double = 1.0

    /// Number of cells (= dots) per side.
    static let dimension = 13

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
    /// Converts a `[[Bool]]` bitmap into `[[DotCell]]`. On cells use the default color (nil).
    /// To color them individually, map over the result on the caller side.
    func toCells() -> [[DotCell]] {
        map { row in row.map { $0 ? .on() : .off } }
    }

    /// Converts to `[[DotCell]]` with on cells painted in the given color.
    func toCells(onColor: Color) -> [[DotCell]] {
        map { row in row.map { $0 ? .on(color: onColor) : .off } }
    }
}
