import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// 使用量の目盛り（3×3 ブロック 10 個 = 100%）の点灯数を検証する。
///
/// 「1 ブロック = 10%」「severity は色だけ変えて目盛りは変えない」という
/// デザイン上の約束が壊れていないかの回帰テスト。
@Suite("Usage block scale Tests")
@MainActor
struct UsageBlockTests {
    /// `UsageBlockScale` と同じ判定式で点灯数を数える。
    private func litBlocks(percent: Double, blocks: Int = 10) -> Int {
        (0..<blocks).filter { index in
            Double(index) / Double(blocks) < percent / 100 - 0.001
        }.count
    }

    @Test("1 ブロック = 10%。境界値でブロック数が期待どおり増える")
    func fillsOneBlockPerTenPercent() {
        #expect(litBlocks(percent: 0) == 0)
        #expect(litBlocks(percent: 5) == 1)
        #expect(litBlocks(percent: 10) == 1)
        #expect(litBlocks(percent: 48) == 5)
        #expect(litBlocks(percent: 62) == 7)
        #expect(litBlocks(percent: 88) == 9)
        #expect(litBlocks(percent: 100) == 10)
    }

    /// 目盛りの総数は使用率によらず 10 個で一定（残量が読める）。
    @Test("ブロックの総数は使用率によらず一定")
    func keepsTotalBlocksConstant() {
        for percent in [0.0, 33.0, 77.0, 100.0] {
            let lit = litBlocks(percent: percent)
            #expect(lit >= 0 && lit <= 10)
        }
    }

    /// 消費済みは塗り、残量は輪郭。形が違うので色が消えても残量が読める。
    @Test("塗りブロックと輪郭ブロックは形で区別できる")
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

    /// `UsageBlockChart` と同じ判定式で 1 列の点灯数を数える。
    private func litColumn(value: Double, maxValue: Double, blocks: Int = 7) -> Int {
        guard value > 0 else { return 0 }
        return max(1, min(blocks, Int(((value / maxValue) * Double(blocks)).rounded())))
    }

    /// 値があるなら最低 1 ドットは光らせる（少額の日が「無い」ように見えないため）。
    @Test("値がある日は最低 1 ドット点灯し、0 の日は点灯しない")
    func alwaysLightsAtLeastOneBlockForNonZero() {
        #expect(litColumn(value: 0, maxValue: 100) == 0)
        #expect(litColumn(value: 0.01, maxValue: 100) == 1)
        #expect(litColumn(value: 100, maxValue: 100) == 7)
        #expect(litColumn(value: 50, maxValue: 100) == 4)
        // 最大値の列でも段数を超えない（丸めで溢れない）。
        #expect(litColumn(value: 99.9, maxValue: 100) == 7)
    }

    /// チャートは 1 枚のドット格子で、**1 段 = 3×3 ブロック**（間に 1 ドットの空き）。
    /// 消費済みは塗り（中心も点灯）、残量は輪郭（中心は消灯）で区別する。
    @Test("チャートは 3×3 ブロックの格子で、点灯は下から積まれる")
    func chartStacksBlocksFromBottom() {
        let rows = 4
        let chart = UsageBlockChart(values: [0, 1, 2], blocksPerColumn: rows)
        let bitmap = chart.bitmap
        // 3 列 × 4 段。ブロック 3 ドット + 空き 1 ドット。
        #expect(bitmap.cols == 3 * 3 + 2)
        #expect(bitmap.rows == rows * 3 + (rows - 1))

        /// 段 `row` / 列 `column` のブロックが塗り（= 消費済み）か。中心セルで判定する。
        func isFilled(row: Int, column: Int) -> Bool {
            bitmap.cell(row: row * 4 + 1, col: column * 4 + 1).on
        }
        /// ブロックの輪郭が描かれているか（残量の □ も格子として見える必要がある）。
        func hasOutline(row: Int, column: Int) -> Bool {
            bitmap.cell(row: row * 4, col: column * 4).on
        }

        // 値 0 の列はどの段も塗られない（輪郭だけ）。
        #expect((0..<rows).allSatisfy { !isFilled(row: $0, column: 0) })
        #expect((0..<rows).allSatisfy { hasOutline(row: $0, column: 0) })
        // 最大値の列は最上段まで塗られる。
        #expect((0..<rows).allSatisfy { isFilled(row: $0, column: 2) })
        // 中間の列は下からのみ塗られる（最上段は輪郭のまま）。
        #expect(isFilled(row: rows - 1, column: 1))
        #expect(!isFilled(row: 0, column: 1))

        // ブロックどうしの間は必ず空く（格子が地続きに見えないように）。
        #expect(!bitmap.cell(row: 3, col: 1).on)
    }

    /// ローディングの波は「値」と見間違えないよう天井まで届かない。
    /// また位相を送れば形が変わる（＝流れて見える）必要がある。
    @Test("ローディングの波は天井に届かず、位相で形が変わる")
    func loadingWaveStaysBelowCeiling() {
        let rows = 7
        let columns = 14

        for phase in [0.0, 0.25, 0.5, 0.75] {
            for column in 0..<columns {
                let height = UsageBlockChart.waveHeight(
                    column: column, columns: columns, rows: rows, phase: phase
                )
                #expect(height >= 0)
                // 段数の半分弱まで（0.45 * 7 ≒ 3）。値のチャートと混ざらない高さに抑える。
                #expect(height <= 3)
            }
        }

        // 位相が違えば列ごとの高さの並びが変わる。
        let atZero = (0..<columns).map {
            UsageBlockChart.waveHeight(column: $0, columns: columns, rows: rows, phase: 0)
        }
        let atHalf = (0..<columns).map {
            UsageBlockChart.waveHeight(column: $0, columns: columns, rows: rows, phase: 0.5)
        }
        #expect(atZero != atHalf)
    }
}
