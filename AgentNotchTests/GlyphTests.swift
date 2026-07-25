import Foundation
import Testing

@testable import AgentNotch

/// グリフ辞書の図柄が意図どおりか検証する。
///
/// 見た目そのものはテストできないが、「点灯マスの座標」は決定的なので
/// アスキーアートに落として比較できる。デザインの意図（形が状態を語る、
/// ドットは格子上に留まる）が壊れていないかの回帰テストになる。
@Suite("Glyph Dictionary Tests")
@MainActor
struct GlyphTests {
    /// ビットマップを `#` / `.` のアスキーアートにする。
    private func ascii(_ bitmap: GlyphBitmap) -> [String] {
        (0..<bitmap.rows).map { row in
            (0..<bitmap.cols).map { col in
                bitmap.cell(row: row, col: col).on ? "#" : "."
            }.joined()
        }
    }

    // MARK: - A · STATE

    @Test("STANDBY は環。位相で半径だけが変わり、点の総数はほぼ保たれる")
    func standbyBreathesRadiusOnly() {
        let contracted = Glyph.state(.standby, phase: 0.75)  // sin = -1 → 半径最小
        let expanded = Glyph.state(.standby, phase: 0.25)  // sin = +1 → 半径最大

        // 中心は常に空（環である）。
        #expect(!contracted.cell(row: 6, col: 6).on)
        #expect(!expanded.cell(row: 6, col: 6).on)

        // 半径が広がると外側のマスが点く。
        let contractedRow = ascii(contracted)[6]
        let expandedRow = ascii(expanded)[6]
        #expect(contractedRow != expandedRow)
        // どちらも左右対称（環が偏っていない）。
        #expect(Array(expandedRow) == Array(expandedRow.reversed()))
    }

    @Test("THINKING は 1 行だけが光る波形で、位相を進めると形が変わる")
    func thinkingIsATravellingWave() {
        let wave = Glyph.state(.thinking, phase: 0)
        // 各列で点灯は 1 マスだけ（波形は 1 本の線）。
        for col in 0..<wave.cols {
            let litInColumn = (0..<wave.rows).filter { wave.cell(row: $0, col: col).on }.count
            #expect(litInColumn == 1)
        }
        #expect(ascii(wave) != ascii(Glyph.state(.thinking, phase: 0.25)))
    }

    @Test("WORKING は塗りの核。位相で半径が 2→4 マスに脈動する")
    func workingPulsesFilledCore() {
        let small = Glyph.state(.working, phase: 0)
        let large = Glyph.state(.working, phase: 0.5)
        let litCount: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter(\.on).count
        }
        #expect(litCount(small) < litCount(large))
        // 中心は常に塗られている（核である）。
        #expect(small.cell(row: 6, col: 6).on)
        #expect(large.cell(row: 6, col: 6).on)
    }

    @Test("SWARM(n) は 3×3 の枠を起動順に n 個埋める")
    func swarmFillsSlotsInOrder() {
        let one = Glyph.state(.swarm(active: 1))
        let five = Glyph.state(.swarm(active: 5))
        // 左上の枠（rows/cols 1〜3）は n=1 で既に点灯。
        #expect(one.cell(row: 1, col: 1).on)
        // 2 番目の枠（cols 5〜7）は n=1 では消灯、n=5 では点灯。
        #expect(!one.cell(row: 1, col: 5).on)
        #expect(five.cell(row: 1, col: 5).on)
        // 9 枠を超える指定は 9 に収める。
        #expect(ascii(Glyph.state(.swarm(active: 99))) == ascii(Glyph.state(.swarm(active: 9))))
    }

    @Test("ALERT は点滅しても形が消えない（消灯側も残す）")
    func alertKeepsShapeWhileBlinking() {
        let lit = Glyph.state(.alert, phase: 0.1)
        let dark = Glyph.state(.alert, phase: 0.9)
        // 形（点灯マスの配置）は同一で、色だけが変わる。
        #expect(ascii(lit) == ascii(dark))
        #expect(lit.cell(row: 2, col: 6).color != dark.cell(row: 2, col: 6).color)
    }

    @Test("COMPLETE は左下からチェックを描き足す")
    func completeDrawsCheckProgressively() {
        let start = Glyph.state(.complete, phase: 0)
        let mid = Glyph.state(.complete, phase: 0.4)
        let end = Glyph.state(.complete, phase: 1)
        let litCount: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter(\.on).count
        }
        #expect(litCount(start) == 0)
        #expect(litCount(start) < litCount(mid))
        #expect(litCount(mid) < litCount(end))
        // 描き始めは左下（x=2, y=6）。
        #expect(Glyph.state(.complete, phase: 0.15).cell(row: 6, col: 2).on)
    }

    // MARK: - A' · RING

    @Test("RING は角度順に点灯し、0% と 100% で点灯数が変わる")
    func ringLightsInAngularOrder() {
        let empty = Glyph.ring(percent: 0, lit: .white, track: .gray)
        let full = Glyph.ring(percent: 100, lit: .white, track: .gray)
        let whiteCount: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter { $0.on && $0.color == .white }.count
        }
        #expect(whiteCount(empty) == 0)
        #expect(whiteCount(full) > 20)
        // 環の形（点灯 + track の総数）は使用率によらず一定。
        let ringCells: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter(\.on).count
        }
        #expect(ringCells(empty) == ringCells(full))
        // 12 時（真上）から点き始める。
        #expect(Glyph.ring(percent: 5, lit: .white, track: .gray).cell(row: 1, col: 6).color == .white)
    }

    // MARK: - B / C / D

    @Test("TASK は輪郭 → 輪郭+芯 → 塗りで段階が読める")
    func taskGlyphsEscalate() {
        #expect(ascii(Glyph.task(.todo)) == ["#####", "#...#", "#...#", "#...#", "#####"])
        #expect(ascii(Glyph.task(.active)) == ["#####", "#...#", "#.#.#", "#...#", "#####"])
        #expect(ascii(Glyph.task(.done)) == ["#####", "#####", "#####", "#####", "#####"])
    }

    @Test("SUBAGENT の菱形と MEMBER の塊は形で区別できる")
    func subagentAndMemberDiffer() {
        #expect(ascii(Glyph.subagentRunning()) == ["..#..", ".###.", "#####", ".###.", "..#.."])
        #expect(ascii(Glyph.subagentIdle()) == ["..#..", ".#.#.", "#...#", ".#.#.", "..#.."])
        // モックの「円」は 5×5 では菱形と同一形になるため、teammate は中央 3×3 の塊にしている。
        #expect(ascii(Glyph.member()) == [".....", ".###.", ".###.", ".###.", "....."])
        #expect(ascii(Glyph.member()) != ascii(Glyph.subagentRunning()))
        #expect(ascii(Glyph.member()) != ascii(Glyph.task(.done)))
    }

    @Test("USAGE ブロックは塗りと輪郭で残量が読める")
    func usageBlockShowsFillState() {
        #expect(ascii(Glyph.usageBlock(filled: true, color: .white)) == ["###", "###", "###"])
        #expect(ascii(Glyph.usageBlock(filled: false, color: .white)) == ["###", "#.#", "###"])
    }

    // MARK: - E · NUMERIC

    @Test("NUMERIC は 5×7 で、字間 1 マスを空ける")
    func numericIsFiveBySevenWithGap() {
        let single = Glyph.number("1")
        #expect(single.rows == 7)
        #expect(single.cols == 5)

        let double = Glyph.number("62")
        // 5 + 1(字間) + 5 = 11
        #expect(double.cols == 11)
        // 字間の列は完全に空。
        #expect((0..<double.rows).allSatisfy { !double.cell(row: $0, col: 5).on })
    }

    @Test("n/m は分子と分母で色を変えられる")
    func numericSupportsPerCharacterColor() {
        let fraction = Glyph.number("3/7") { index in index == 0 ? .white : .gray }
        let numerator = (0..<fraction.rows).compactMap { fraction.cell(row: $0, col: 0).color }
        #expect(numerator.allSatisfy { $0 == .white })
    }

    @Test("FRAMED は 13×13 枠の中央に数字を収める")
    func framedNumberCentersInStateGrid() {
        let framed = Glyph.framedNumber("62")
        #expect(framed.rows == 13)
        #expect(framed.cols == 13)
        // 上下 3 マスは空（枠の余白）。
        #expect((0..<framed.cols).allSatisfy { !framed.cell(row: 0, col: $0).on })
        #expect((0..<framed.cols).allSatisfy { !framed.cell(row: 12, col: $0).on })
        // 中央付近には点灯がある。
        #expect((0..<framed.cols).contains { framed.cell(row: 6, col: $0).on })
    }
}
