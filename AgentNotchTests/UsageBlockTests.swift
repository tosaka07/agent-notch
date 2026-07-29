import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Verifies the lit-block count on the usage scale (ten 3x3 blocks = 100%).
///
/// Regression tests for two design promises: one block equals 10%, and severity
/// changes only the color, never the scale.
@Suite("Usage block scale Tests")
@MainActor
struct UsageBlockTests {
    /// Calls the scale's own predicate. Reimplementing it here would let the test keep passing
    /// after the production formula changed, which is the opposite of what it is for.
    private func litBlocks(percent: Double, blocks: Int = 10) -> Int {
        UsageBlockScale.litBlocks(blocks: blocks, usedPercent: percent)
    }

    @Test("One block equals 10%, and the count steps up at the boundaries")
    func fillsOneBlockPerTenPercent() {
        #expect(litBlocks(percent: 0) == 0)
        #expect(litBlocks(percent: 5) == 1)
        #expect(litBlocks(percent: 10) == 1)
        #expect(litBlocks(percent: 48) == 5)
        #expect(litBlocks(percent: 62) == 7)
        #expect(litBlocks(percent: 88) == 9)
        #expect(litBlocks(percent: 100) == 10)
    }

    /// The scale always shows 10 blocks regardless of utilization, so the remaining
    /// headroom stays readable.
    @Test("The total block count is independent of utilization")
    func keepsTotalBlocksConstant() {
        for percent in [0.0, 33.0, 77.0, 100.0] {
            let lit = litBlocks(percent: percent)
            #expect(lit >= 0 && lit <= 10)
        }
    }

    /// Out-of-range input reaches the scale from the API's percentages, so it clamps rather than
    /// lighting a negative or eleventh block.
    @Test("Percentages outside 0-100 are clamped, not extrapolated")
    func clampsOutOfRangePercent() {
        #expect(litBlocks(percent: -50) == 0)
        #expect(litBlocks(percent: 250) == 10)
    }

    /// Blocks fill left to right: a block can only be lit if every block before it is. A
    /// predicate that lit them out of order would still satisfy a count-only assertion.
    @Test("Lit blocks form an unbroken run from the left")
    func fillsContiguouslyFromTheLeft() {
        for percent in stride(from: 0.0, through: 100.0, by: 6.5) {
            let filled = (0..<10).map {
                UsageBlockScale.isFilled(index: $0, blocks: 10, usedPercent: percent)
            }
            let firstUnlit = filled.firstIndex(of: false) ?? filled.count
            #expect(
                filled[firstUnlit...].allSatisfy { !$0 },
                "percent \(percent) lit a block after an unlit one"
            )
        }
    }

    /// The block count is configurable, and one block has to mean 100/blocks percent at any
    /// count — otherwise a compact scale would misreport.
    @Test("A custom block count rescales what one block means")
    func honoursCustomBlockCount() {
        #expect(UsageBlockScale.litBlocks(blocks: 4, usedPercent: 0) == 0)
        #expect(UsageBlockScale.litBlocks(blocks: 4, usedPercent: 25) == 1)
        #expect(UsageBlockScale.litBlocks(blocks: 4, usedPercent: 50) == 2)
        #expect(UsageBlockScale.litBlocks(blocks: 4, usedPercent: 100) == 4)
        #expect(UsageBlockScale.litBlocks(blocks: 5, usedPercent: 20) == 1)
    }

    /// Consumed blocks are filled and remaining ones outlined, so headroom stays
    /// readable by shape even without color.
    @Test("Filled and outlined blocks are distinguishable by shape")
    func filledAndEmptyBlocksDifferInShape() {
        let filled = Glyph.usageBlock(filled: true, color: .white)
        let empty = Glyph.usageBlock(filled: false, color: .white)
        let ascii: (GlyphBitmap) -> [String] = { bitmap in
            (0..<bitmap.rows).map { row in
                (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0).on ? "#" : "." }.joined()
            }
        }
        #expect(ascii(filled) == ["###", "###", "###"])
        #expect(ascii(empty) == ["###", "#.#", "###"])
    }

    // MARK: - Daily cost chart

    /// Counts the filled tiers in one column of the **real** chart bitmap, judged by each block's
    /// centre cell. Going through the bitmap rather than a copy of the height formula is the point:
    /// the scaling lives inside `bitmap`, and a replica here would not notice it changing.
    private func litTiers(values: [Double], column: Int, rows: Int = 7) -> Int {
        let bitmap = UsageBlockChart(values: values, blocksPerColumn: rows).bitmap
        return (0..<rows).count { bitmap.cell(row: $0 * 4 + 1, col: column * 4 + 1).on }
    }

    /// Any non-zero value lights at least one dot, so a low-spend day does not look
    /// like no day at all.
    @Test("A day with a value lights at least one dot; a zero day lights none")
    func alwaysLightsAtLeastOneBlockForNonZero() {
        // Heights are relative to the largest value in the set, so 100 is the ceiling here.
        let values: [Double] = [0, 0.01, 50, 99.9, 100]

        #expect(litTiers(values: values, column: 0) == 0)
        // A value far below the ceiling still gets a tier rather than disappearing.
        #expect(litTiers(values: values, column: 1) == 1)
        #expect(litTiers(values: values, column: 2) == 4)
        // Even the tallest column stays within the row count; rounding must not overflow.
        #expect(litTiers(values: values, column: 3) == 7)
        #expect(litTiers(values: values, column: 4) == 7)
    }

    /// Heights are relative to the set's own peak, so the same number reads differently depending
    /// on the days around it — scaling against a fixed ceiling would flatten every quiet week.
    @Test("Column heights are relative to the peak of the set")
    func scalesToTheSetsPeak() {
        // 5 is the peak of its own set and so reaches the top, while the same 5 alongside a 10
        // reaches only halfway.
        #expect(litTiers(values: [5], column: 0) == 7)
        #expect(litTiers(values: [5, 10], column: 0) == 4)
        #expect(litTiers(values: [5, 10], column: 1) == 7)
    }

    /// An all-zero set is the shape a fresh install produces. It must render an empty grid rather
    /// than divide by a zero peak.
    @Test("An all-zero set renders an empty grid without dividing by zero")
    func handlesAllZeroValues() {
        let bitmap = UsageBlockChart(values: [0, 0, 0], blocksPerColumn: 7).bitmap

        #expect(bitmap.cols == 3 * 3 + 2)
        #expect((0..<3).allSatisfy { litTiers(values: [0, 0, 0], column: $0) == 0 })
    }

    /// An empty set has no columns to scale at all; the grid still needs a valid size, since the
    /// view is laid out before any data arrives.
    @Test("An empty set still produces a one-column grid")
    func handlesEmptyValues() {
        let bitmap = UsageBlockChart(values: [], blocksPerColumn: 7).bitmap

        #expect(bitmap.cols == 3)
        #expect(bitmap.rows == 7 * 3 + 6)
    }

    // MARK: - Rise-in

    /// Columns reach their target staggered from the left, so the values look like they fill in
    /// behind the loading wave. The endpoints have to be exact, or the chart would either start
    /// non-empty or never quite arrive.
    @Test("The rise starts empty and ends exactly on target")
    func revealEndpointsAreExact() {
        for column in 0..<14 {
            #expect(
                UsageBlockChart.revealed(target: 5, column: column, columns: 14, progress: 1) == 5
            )
            #expect(
                UsageBlockChart.revealed(target: 5, column: column, columns: 14, progress: 0) == 0
            )
        }
    }

    @Test("A rise in progress never exceeds its target or goes negative")
    func revealStaysWithinTarget() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            for column in 0..<14 {
                let lit = UsageBlockChart.revealed(
                    target: 6, column: column, columns: 14, progress: progress
                )
                #expect(lit >= 0 && lit <= 6, "progress \(progress) column \(column) gave \(lit)")
            }
        }
    }

    /// The stagger is what makes the fill read as left-to-right motion; without it every column
    /// would rise together and the wave would appear to stop dead.
    @Test("Earlier columns lead later ones during the rise")
    func revealStaggersFromTheLeft() {
        let heights = (0..<14).map {
            UsageBlockChart.revealed(target: 7, column: $0, columns: 14, progress: 0.5)
        }

        #expect(heights.first! > heights.last!)
        // Non-increasing left to right: no column may overtake one to its left.
        #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 >= $1 })
    }

    /// A single-column chart divides by `columns - 1`, so it is the case that would produce a NaN
    /// position and a zero-height column that never fills.
    @Test("A single column rises without dividing by zero")
    func revealHandlesSingleColumn() {
        #expect(UsageBlockChart.revealed(target: 4, column: 0, columns: 1, progress: 1) == 4)
        #expect(UsageBlockChart.revealed(target: 4, column: 0, columns: 1, progress: 0.5) > 0)
    }

    @Test("A chart mid-rise draws shorter columns than the finished one")
    func chartRespectsRevealProgress() {
        let values: [Double] = [10, 10, 10]
        let mid = UsageBlockChart(values: values, revealProgress: 0.3, blocksPerColumn: 7).bitmap
        let done = UsageBlockChart(values: values, blocksPerColumn: 7).bitmap

        func litTiers(in bitmap: GlyphBitmap, column: Int) -> Int {
            (0..<7).count { bitmap.cell(row: $0 * 4 + 1, col: column * 4 + 1).on }
        }
        #expect(litTiers(in: mid, column: 2) < litTiers(in: done, column: 2))
    }

    // MARK: - Axis metrics

    /// The floor label is pushed down by the descender so its baseline lands on the grid's bottom
    /// edge. A non-positive value would leave it floating above the axis.
    @Test("The descender is positive and grows with font size")
    func descenderGrowsWithFontSize() {
        let small = UsageBlockChart.descender(for: 8)
        let large = UsageBlockChart.descender(for: 16)

        #expect(small > 0)
        #expect(large > small)
    }

    /// The chart is a single dot grid where **one tier is a 3x3 block**, separated by a
    /// one-dot gap. Consumed tiers are filled (center lit) and remaining ones outlined
    /// (center dark).
    @Test("The chart is a grid of 3x3 blocks that fills from the bottom up")
    func chartStacksBlocksFromBottom() {
        let rows = 4
        let chart = UsageBlockChart(values: [0, 1, 2], blocksPerColumn: rows)
        let bitmap = chart.bitmap
        // 3 columns by 4 tiers: a 3-dot block plus a 1-dot gap each.
        #expect(bitmap.cols == 3 * 3 + 2)
        #expect(bitmap.rows == rows * 3 + (rows - 1))

        /// Whether the block at tier `row`, column `column` is filled (consumed),
        /// judged by its center cell.
        func isFilled(row: Int, column: Int) -> Bool {
            bitmap.cell(row: row * 4 + 1, col: column * 4 + 1).on
        }
        /// Whether the block's outline is drawn — remaining tiers must still read as a grid.
        func hasOutline(row: Int, column: Int) -> Bool {
            bitmap.cell(row: row * 4, col: column * 4).on
        }

        // A zero-valued column fills no tier; only outlines remain.
        #expect((0..<rows).allSatisfy { !isFilled(row: $0, column: 0) })
        #expect((0..<rows).allSatisfy { hasOutline(row: $0, column: 0) })
        // The tallest column fills up to the top tier.
        #expect((0..<rows).allSatisfy { isFilled(row: $0, column: 2) })
        // A mid-range column fills only from the bottom; the top tier stays outlined.
        #expect(isFilled(row: rows - 1, column: 1))
        #expect(!isFilled(row: 0, column: 1))

        // Blocks are always separated so the grid does not read as one solid mass.
        #expect(!bitmap.cell(row: 3, col: 1).on)
    }

    /// The loading wave never reaches the ceiling, so it cannot be mistaken for data,
    /// and advancing the phase must change its shape so it reads as flowing.
    @Test("The loading wave stays below the ceiling and changes shape with phase")
    func loadingWaveStaysBelowCeiling() {
        let rows = 7
        let columns = 14

        for phase in [0.0, 0.25, 0.5, 0.75] {
            for column in 0..<columns {
                let height = UsageBlockChart.waveHeight(
                    column: column, columns: columns, rows: rows, phase: phase
                )
                #expect(height >= 0)
                // Just under half the tiers (0.45 * 7 is about 3), low enough not to be
                // confused with a real chart.
                #expect(height <= 3)
            }
        }

        // A different phase produces a different sequence of column heights.
        let atZero = (0..<columns).map {
            UsageBlockChart.waveHeight(column: $0, columns: columns, rows: rows, phase: 0)
        }
        let atHalf = (0..<columns).map {
            UsageBlockChart.waveHeight(column: $0, columns: columns, rows: rows, phase: 0.5)
        }
        #expect(atZero != atHalf)
    }
}
