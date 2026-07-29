import AppKit
import SwiftUI

/// The product symbol, used by the app icon and the menu bar icon.
///
/// # Invent no new shapes
/// Having **no drawing rule that exists only for the logo** is what proves this language is
/// consistent. The symbol is the ring already in the dictionary (`Glyph.ringCellIndices` =
/// STANDBY's 13×13 ring) with the **middle 5 cells of the top edge removed**. That is the
/// physical notch cutout itself, and at the same time an eye keeping watch. The center 3×3 is
/// the pupil (the same fill unit as `Glyph.usageBlock`).
///
/// ```
/// ...#   #...      ← the middle 5 cells of the top edge are the notch cutout
/// ..###...###..
/// .##.......##.
/// .##..###..##.
/// .#...###...#.    ← the center 3×3 is the pupil
/// .#...###...#.
/// .#.........#.
/// .##.......##.
/// ..###...###..
/// ...#######...
/// ```
///
/// # Two forms, large and small
/// - `outlineCells` — the ring as-is. For places it can be shown large, like the app icon
/// - `solidCells` — a filled silhouette. In the menu bar (18pt square) the gaps between dots
///   collapse and smear, so fill the outline and keep only the shape. A one-row cutout also
///   disappears at that size, so it is deepened to two rows
enum ProductMark {
    /// One side of the grid. 13×13, the same as the dictionary's state glyphs.
    static let size = Glyph.stateSize

    /// The notch cutout: the middle 5 cells of the top edge (row 1).
    private static let cutoutColumns = 4...8

    /// The ring's cells with the cutout removed.
    static let outlineCells: [GridCell] = {
        Glyph.ringCellIndices.compactMap { index in
            let cell = GridCell(col: index % size, row: index / size)
            if cell.row == 1, cutoutColumns.contains(cell.col) { return nil }
            return cell
        }
    }()

    /// The center pupil (3×3). Placed fainter than the ring in the app icon.
    static let pupilCells: [GridCell] = (5...7).flatMap { row in
        (5...7).map { GridCell(col: $0, row: row) }
    }

    /// The filled variant. Each row of the ring is filled from its leftmost to rightmost cell,
    /// with a two-row cutout removed.
    ///
    /// In the menu bar a single dot is under 1pt, so leaving gaps smears the shape into a plain
    /// circle. Filling it at least preserves the outline — whether the cutout is there.
    static let solidCells: [GridCell] = {
        var byRow: [Int: (min: Int, max: Int)] = [:]
        for index in Glyph.ringCellIndices {
            let col = index % size
            let row = index / size
            let current = byRow[row] ?? (min: col, max: col)
            byRow[row] = (min: Swift.min(current.min, col), max: Swift.max(current.max, col))
        }
        return byRow.sorted { $0.key < $1.key }.flatMap { row, span in
            (span.min...span.max).compactMap { col in
                // The cutout is two rows deep; one row is under 1px at 18pt and vanishes.
                if row <= 2, cutoutColumns.contains(col) { return nil }
                return GridCell(col: col, row: row)
            }
        }
    }()

    struct GridCell: Hashable, Sendable {
        let col: Int
        let row: Int
    }
}

// MARK: - Rendering

extension ProductMark {
    /// Template image for the menu bar.
    ///
    /// As a template, macOS tints it to match light/dark, selection state, and vibrancy.
    /// **Do not bake in a color** — it would stand out in light mode or when the menu is selected.
    ///
    /// The Liquid Glass menu bar lets the background show through, so a thin outline loses to
    /// whatever is behind it. That is another reason `solidCells` fills the cells with no gaps.
    static func menuBarImage(pointSize: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let pitch = rect.width / CGFloat(size)
            NSColor.black.setFill()
            for cell in solidCells {
                // NSImage's coordinate origin is at the bottom, so flip the row.
                NSRect(
                    x: CGFloat(cell.col) * pitch,
                    y: rect.height - CGFloat(cell.row + 1) * pitch,
                    width: pitch,
                    height: pitch
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Agent Notch"
        return image
    }
}

#Preview("Product Mark") {
    VStack(spacing: 24) {
        // The app icon form (ring + pupil).
        GlyphView(
            bitmap: GlyphBitmap.square(ProductMark.size, on: DSColors.ink) { x, y in
                ProductMark.outlineCells.contains(ProductMark.GridCell(col: x, row: y))
            },
            dot: 8,
            gap: 4
        )
        // The menu bar form (filled).
        GlyphView(
            bitmap: GlyphBitmap.square(ProductMark.size, on: DSColors.ink) { x, y in
                ProductMark.solidCells.contains(ProductMark.GridCell(col: x, row: y))
            },
            dot: 8,
            gap: 0
        )
    }
    .padding(32)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
