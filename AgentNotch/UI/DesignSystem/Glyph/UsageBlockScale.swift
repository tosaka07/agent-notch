import AppKit
import SwiftUI

/// The usage tick scale.
///
/// Ten of the glyph dictionary's D (3×3 block) laid out to represent 100%. **One block = 10%.**
/// Discrete blocks rather than a continuous bar, for two reasons:
/// - "how many blocks are left" reads as a number
/// - **severity changes only the color, never the ticks**, so API-provided severity and our own
///   thresholds ride the same scale
struct UsageBlockScale: View {
    /// Usage from 0 to 100.
    let usedPercent: Double
    /// Color of consumed blocks. Severity changes only the color.
    var color: Color = DSColors.ink
    /// Block count. 10 blocks = 100% (10% each).
    var blocks: Int = 10
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// Spacing between blocks.
    var spacing: CGFloat = 5

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    /// Whether the block at `index` counts as consumed.
    ///
    /// Kept as a static so tests exercise the real predicate rather than a copy of it — the scale
    /// is the one place the "one block = 10%" promise is enforced, and a test that reimplements the
    /// comparison would keep passing after the promise broke.
    ///
    /// The 0.001 margin keeps a boundary percentage from lighting an extra block: at exactly 10%,
    /// `1/10 < 0.1` must stay false despite binary floating point.
    static func isFilled(index: Int, blocks: Int, usedPercent: Double) -> Bool {
        let clamped = min(max(usedPercent, 0), 100)
        return Double(index) / Double(blocks) < clamped / 100 - 0.001
    }

    /// How many blocks read as consumed. One block = 10% at the default block count.
    static func litBlocks(blocks: Int, usedPercent: Double) -> Int {
        (0..<blocks).count { isFilled(index: $0, blocks: blocks, usedPercent: usedPercent) }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<blocks, id: \.self) { index in
                GlyphView(
                    bitmap: Glyph.usageBlock(
                        filled: Self.isFilled(
                            index: index,
                            blocks: blocks,
                            usedPercent: clampedPercent
                        ),
                        color: color
                    ),
                    dot: dot,
                    gap: gap
                )
            }
        }
        .accessibilityElement()
        .accessibilityValue(L("\(Int(clampedPercent.rounded())) percent"))
    }
}

/// A dot chart of daily cost.
///
/// One column = one day. **One step = a 3×3 block glyph**, stacked from the bottom so height
/// carries the amount. Consumed is filled (■) and remaining is outline (□), so it reads exactly
/// like the dictionary's D. Any nonzero value lights at least one step, so a small day never
/// looks absent. Only the latest column is colored more strongly, marking "today".
///
/// # Why one step is 3×3
/// At one dot per step, keeping the dots fine makes the chart so small it huddles at the left of
/// the card. **Keeping dots at 2pt and grouping the unit into 3×3** nearly doubles the figure's
/// size without changing its grain.
/// The whole thing is built as a single bitmap, so drawing is one `GlyphView` call.
///
/// # Giving it axes
/// With the ticks placed outside, the figure just sits there and you cannot read which column is
/// when, or how high the ceiling is. So the labels belong to the chart itself:
/// - **Vertical axis**: peak amount on the top row, 0 on the bottom row. Aligned to the row
///   heights, so "this height is 12 dollars" reads
/// - **Horizontal axis**: dates directly below the leftmost and rightmost columns. Aligned to
///   the chart width, so they correspond to the columns
struct UsageBlockChart: View {
    /// Values, oldest first from the left.
    let values: [Double]
    /// Tick label for the leftmost column (the oldest day).
    var startLabel: String?
    /// Tick label for the rightmost column (the latest day).
    var endLabel: String?
    /// Label for the vertical axis ceiling (the peak amount, etc.).
    var peakLabel: String?
    /// Rise-in progress (0–1).
    ///
    /// Below 1, each column is drawn **partway up from the bottom toward its target height**.
    /// Columns start slightly staggered from the left, so the values look like they fill in after
    /// the wave recedes (continuing straight out of the loading wave).
    var revealProgress: Double = 1
    /// Loading phase (0–1).
    ///
    /// When set, **a wave flowing left to right** is drawn instead of `values`. A still, empty
    /// grid would be misread as "the aggregation finished and this is the result (all zero)", so
    /// it is replaced by motion that cannot be read as a number — the same idea as the gauge's
    /// spinning ring.
    var loadingPhase: Double?
    /// Steps per column (the vertical resolution).
    var blocksPerColumn: Int = 7
    var color: Color = DSColors.ink.opacity(0.62)
    var latestColor: Color = DSColors.ink
    /// One dot's side. A step is 3×3, so its height is `dot * 3 + gap * 2`.
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// Font for the axis labels. Pass one matching the caller's text-size setting.
    var labelFont: Font = DSTypography.mono(8)
    /// Font size of the axis labels. Pass the same value as `labelFont`.
    ///
    /// Aligning the floor label's (`$0`) baseline to the grid's bottom edge needs the descender
    /// amount, and the size cannot be read back out of a `Font`, so it is taken separately.
    var labelFontSize: CGFloat = 8
    /// Width of the vertical axis labels. Placed outside the grid's left edge, right-aligned in
    /// this width, consuming no layout width.
    ///
    /// Amounts can have many digits, so pass a width where `$1,234` fits unshrunk. But
    /// **it must not exceed the gap between the grid and the card edge** — since it consumes no
    /// width, anything past that is clipped by the card's corner radius. At the "large" text
    /// size, six characters like `$1,234` can lose a few points.
    var axisWidth: CGFloat = 44

    /// Side of the block making up one step / column, in dots.
    private let blockSize = 3
    /// Space between blocks, in dots.
    private let blockSpacing = 1

    private var maxValue: Double { max(values.max() ?? 0, .leastNonzeroMagnitude) }

    /// Pitch in dot units.
    private var pitch: CGFloat { dot + gap }

    /// Rendered size of one step (= one block). Used to align axis labels to rows.
    private var blockLength: CGFloat {
        CGFloat(blockSize) * dot + CGFloat(blockSize - 1) * gap
    }

    /// Rendered size of the grid. Used to align axis labels to columns and rows.
    private var gridWidth: CGFloat {
        let cols = CGFloat(max(1, values.count))
        return cols * blockLength + (cols - 1) * CGFloat(blockSpacing) * pitch
    }

    private var gridHeight: CGFloat {
        let rows = CGFloat(max(1, blocksPerColumn))
        return rows * blockLength + (rows - 1) * CGFloat(blockSpacing) * pitch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Remaining is shown by outline blocks, so no ghost — tinting the spaces between
            // blocks as well would turn the grid into a solid mass.
            GlyphView(bitmap: bitmap, dot: dot, gap: gap)
            horizontalAxis
        }
        // The vertical axis **consumes no width**; it is offset outside the grid's left edge.
        //
        // Laying out an HStack of "label / grid / matching spacer" is another option, but the
        // spacer shrinks when width runs short, shifting the grid right by the label's width.
        // A fixed width avoids the shift but inflates the card's minimum width and eats the
        // page's side margins. **Taking up no width** causes neither problem.
        .overlay(alignment: .topLeading) {
            verticalAxis
                .frame(width: axisWidth, alignment: .trailing)
                .offset(x: -(axisWidth + 6))
        }
        // Center the fixed-width grid in the card.
        .frame(maxWidth: .infinity)
        .font(labelFont)
        .foregroundStyle(DSColors.inkMute)
    }

    /// Vertical axis. Ceiling (peak) and floor (0) aligned to the step heights.
    @ViewBuilder
    private var verticalAxis: some View {
        if let peakLabel {
            // Ceiling and floor align to **the grid's outer edges**. Centering them on the steps
            // pulls the ticks inward and they stop reading as an axis — an axis exists to say
            // "nothing above this line" and "here is 0".
            VStack(alignment: .trailing, spacing: 0) {
                Text(peakLabel)
                    .frame(height: blockLength, alignment: .top)
                Spacer(minLength: 0)
                Text("$0")
                    .frame(height: blockLength, alignment: .bottom)
                    // `.bottom` aligns the text box's bottom edge, so the glyphs float by the
                    // descender. The floor tick should have **its baseline on the grid's bottom
                    // edge**, so push it down by that amount.
                    .offset(y: Self.descender(for: labelFontSize))
            }
            .frame(height: gridHeight)
            .lineLimit(1)
            // Insurance for many digits. If this kicks in often, axisWidth is too small —
            // once shrinking becomes routine, the specified font size stops meaning anything.
            .minimumScaleFactor(0.9)
        }
    }

    /// Horizontal axis. Placed directly below the leftmost and rightmost columns, aligned to the
    /// chart width.
    ///
    /// The dates are a secondary "from when to when", so they sit one step smaller than the
    /// amount (the ceiling value). At the same size, two ticks rank equally and it is unclear
    /// which to read first.
    @ViewBuilder
    private var horizontalAxis: some View {
        if startLabel != nil || endLabel != nil {
            HStack(spacing: 0) {
                Text(startLabel ?? "")
                Spacer(minLength: 0)
                Text(endLabel ?? "")
            }
            .font(DSTypography.mono(max(7, labelFontSize - 2)))
            .frame(width: gridWidth)
        }
    }

    /// Kept internal so tests can verify the lit pattern.
    var bitmap: GlyphBitmap {
        let rows = max(1, blocksPerColumn)
        let cols = max(1, values.count)
        let step = blockSize + blockSpacing
        let gridRows = rows * blockSize + (rows - 1) * blockSpacing
        let gridCols = cols * blockSize + (cols - 1) * blockSpacing
        var cells = Array(repeating: Array(repeating: DotCell.off, count: gridCols), count: gridRows)

        for (column, value) in values.enumerated() {
            let lit: Int
            let litColor: Color
            if let loadingPhase {
                lit = Self.waveHeight(column: column, columns: cols, rows: rows, phase: loadingPhase)
                // This is not a value, so it should not assert itself: just one step brighter
                // than the outline.
                litColor = DSColors.inkMute
            } else {
                // Any nonzero value lights at least one step, so a tiny day never looks absent.
                let target =
                    value > 0
                    ? max(1, min(rows, Int(((value / maxValue) * Double(rows)).rounded())))
                    : 0
                lit = Self.revealed(
                    target: target,
                    column: column,
                    columns: cols,
                    progress: revealProgress
                )
                litColor = column == values.count - 1 ? latestColor : color
            }

            for row in 0..<rows {
                let isFilled = row >= rows - lit
                let blockColor = isFilled ? litColor : DSColors.inkGhost
                let originRow = row * step
                let originColumn = column * step

                for y in 0..<blockSize {
                    for x in 0..<blockSize {
                        // Consumed is filled (■), remaining is outline (□) — the same reading
                        // as the dictionary's D.
                        let isEdge = y == 0 || y == blockSize - 1 || x == 0 || x == blockSize - 1
                        guard isFilled || isEdge else { continue }
                        cells[originRow + y][originColumn + x] = .on(color: blockColor)
                    }
                }
            }
        }
        return GlyphBitmap(rows: gridRows, cols: gridCols, cells: cells)
    }

    /// Step count partway through the rise. Columns reach their target slightly staggered,
    /// left to right.
    static func revealed(target: Int, column: Int, columns: Int, progress: Double) -> Int {
        guard progress < 1 else { return target }
        guard progress > 0 else { return 0 }
        // Column delay is capped at 40% of the total, so even the last column finishes rising
        // within the remaining 60%.
        let stagger = 0.4
        let position = Double(column) / Double(max(1, columns - 1))
        let local = (progress - position * stagger) / (1 - stagger)
        guard local > 0 else { return 0 }
        // Overshoot slightly at the end and come back (the same click-into-place feel as the
        // gauge's settle).
        let eased = min(1.06, easeOutBack(min(1, local)))
        return max(0, min(target, Int((Double(target) * eased).rounded())))
    }

    private static func easeOutBack(_ t: Double) -> Double {
        let overshoot = 1.1
        let p = t - 1
        return 1 + (overshoot + 1) * (p * p * p) + overshoot * (p * p)
    }

    /// The font's descender amount, returned as a positive value.
    static func descender(for fontSize: CGFloat) -> CGFloat {
        -NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).descender
    }

    /// The loading wave. One period spans the full width, and advancing the phase makes it flow
    /// left to right. It never reaches the ceiling — the height is held to just under half the
    /// step count so it is not mistaken for a chart of values.
    static func waveHeight(column: Int, columns: Int, rows: Int, phase: Double) -> Int {
        let position = Double(column) / Double(max(1, columns - 1))
        let wave = (sin((position - phase) * 2 * .pi) + 1) / 2
        return max(0, min(rows, Int((wave * Double(rows) * 0.45).rounded())))
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
