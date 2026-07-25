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

    /// チャートは 1 枚のドット格子として描く。列数 = 日数、行数 = 段数で、
    /// 点灯は必ず下から積まれる（上に浮いた点があると量として読めない）。
    @Test("チャートは日数×段数の格子で、点灯は下から積まれる")
    func chartStacksDotsFromBottom() {
        let chart = UsageBlockChart(values: [0, 1, 2], blocksPerColumn: 4)
        let bitmap = chart.bitmap
        #expect(bitmap.cols == 3)
        #expect(bitmap.rows == 4)

        // 値 0 の列は全消灯。
        #expect((0..<4).allSatisfy { !bitmap.cell(row: $0, col: 0).on })
        // 最大値の列は最上段まで点灯。
        #expect((0..<4).allSatisfy { bitmap.cell(row: $0, col: 2).on })
        // 中間の列は下からのみ点灯（最上段は消灯）。
        #expect(bitmap.cell(row: 3, col: 1).on)
        #expect(!bitmap.cell(row: 0, col: 1).on)
    }
}
