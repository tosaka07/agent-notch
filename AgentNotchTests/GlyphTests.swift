import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Verifies that the figures in the glyph dictionary match their intent.
///
/// The visual result itself cannot be tested, but the coordinates of the lit cells
/// are deterministic, so a figure can be rendered as ASCII art and compared. These
/// act as regression tests for the design intent: the shape communicates the state,
/// and dots stay on the grid.
@Suite("Glyph Dictionary Tests")
@MainActor
struct GlyphTests {
    /// Renders a bitmap as `#` / `.` ASCII art.
    private func ascii(_ bitmap: GlyphBitmap) -> [String] {
        (0..<bitmap.rows).map { row in
            (0..<bitmap.cols).map { col in
                bitmap.cell(row: row, col: col).on ? "#" : "."
            }.joined()
        }
    }

    // MARK: - A · STATE

    @Test("STANDBY is a ring: phase changes only the radius, keeping the dot count roughly constant")
    func standbyBreathesRadiusOnly() {
        let contracted = Glyph.state(.standby, phase: 0.75)  // sin = -1, minimum radius
        let expanded = Glyph.state(.standby, phase: 0.25)  // sin = +1, maximum radius

        // The center is always empty; this is a ring.
        #expect(!contracted.cell(row: 6, col: 6).on)
        #expect(!expanded.cell(row: 6, col: 6).on)

        // A larger radius lights cells further out.
        let contractedRow = ascii(contracted)[6]
        let expandedRow = ascii(expanded)[6]
        #expect(contractedRow != expandedRow)
        // Both are left-right symmetric, so the ring is not lopsided.
        #expect(Array(expandedRow) == Array(expandedRow.reversed()))
    }

    @Test("THINKING is a waveform lighting one cell per column, and its shape changes with phase")
    func thinkingIsATravellingWave() {
        let wave = Glyph.state(.thinking, phase: 0)
        // Exactly one lit cell per column: the waveform is a single line.
        for col in 0..<wave.cols {
            let litInColumn = (0..<wave.rows).filter { wave.cell(row: $0, col: col).on }.count
            #expect(litInColumn == 1)
        }
        #expect(ascii(wave) != ascii(Glyph.state(.thinking, phase: 0.25)))
    }

    @Test("WORKING is a filled core whose radius pulses between 2 and 4 cells with phase")
    func workingPulsesFilledCore() {
        let small = Glyph.state(.working, phase: 0)
        let large = Glyph.state(.working, phase: 0.5)
        let litCount: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter(\.on).count
        }
        #expect(litCount(small) < litCount(large))
        // The center is always filled; this is a core.
        #expect(small.cell(row: 6, col: 6).on)
        #expect(large.cell(row: 6, col: 6).on)
    }

    @Test("SWARM(n) fills n of the 3x3 slots in launch order")
    func swarmFillsSlotsInOrder() {
        let one = Glyph.state(.swarm(active: 1))
        let five = Glyph.state(.swarm(active: 5))
        // The top-left slot (rows/cols 1-3) is already lit at n=1.
        #expect(one.cell(row: 1, col: 1).on)
        // The second slot (cols 5-7) is dark at n=1 and lit at n=5.
        #expect(!one.cell(row: 1, col: 5).on)
        #expect(five.cell(row: 1, col: 5).on)
        // Anything above 9 clamps to 9 slots.
        #expect(ascii(Glyph.state(.swarm(active: 99))) == ascii(Glyph.state(.swarm(active: 9))))
    }

    @Test("ALERT keeps its shape while blinking; the dark phase stays visible")
    func alertKeepsShapeWhileBlinking() {
        let lit = Glyph.state(.alert, phase: 0.1)
        let dark = Glyph.state(.alert, phase: 0.9)
        // The shape (which cells are lit) is identical; only the color changes.
        #expect(ascii(lit) == ascii(dark))
        #expect(lit.cell(row: 2, col: 6).color != dark.cell(row: 2, col: 6).color)
    }

    @Test("QUESTION is a distinct question mark and keeps its shape while blinking")
    func questionKeepsShapeWhileBlinking() {
        let lit = Glyph.state(.question, phase: 0.1)
        let dark = Glyph.state(.question, phase: 0.9)

        #expect(ascii(lit) == ascii(dark))
        #expect(ascii(lit) != ascii(Glyph.state(.alert, phase: 0.1)))
        #expect(lit.cell(row: 2, col: 6).on)
        #expect(lit.cell(row: 9, col: 5).on)
        #expect(!lit.cell(row: 8, col: 5).on)
        #expect(lit.cell(row: 2, col: 6).color != dark.cell(row: 2, col: 6).color)
    }

    @Test("The glyph follows the first item in the shared interruption queue")
    func pendingInterruptionMapsToItsGlyph() {
        let session = UnifiedSession(
            id: "question-glyph", agentType: .claudeCode, status: .permissionWaiting)
        session.pendingQuestion = PendingQuestion(toolUseId: "question", questions: [])
        #expect(session.glyphState == .question)

        session.pendingPermissions = [
            PermissionRequest(
                id: "permission", agentType: .claudeCode, sessionId: session.id,
                toolName: "Bash", toolInput: [:], toolUseId: "permission",
                timestamp: Date(), canRespond: true
            )
        ]
        #expect(session.glyphState == .question)

        session.pendingInterruptions.remove(kind: .question, toolUseId: "question")
        #expect(session.glyphState == .alert)
    }

    @Test("A waiting session without queue metadata keeps the alert fallback")
    func missingInterruptionUsesAlertFallback() {
        let session = UnifiedSession(
            id: "missing-interruption",
            agentType: .claudeCode,
            status: .permissionWaiting
        )

        #expect(session.glyphState == .alert)
    }

    @Test("COMPLETE draws the check mark starting from the bottom left")
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
        // Drawing starts at the bottom left (x=2, y=6).
        #expect(Glyph.state(.complete, phase: 0.15).cell(row: 6, col: 2).on)
    }

    // MARK: - A' · RING

    @Test("RING lights cells by angle, and the lit count differs between 0% and 100%")
    func ringLightsInAngularOrder() {
        let empty = Glyph.ring(percent: 0, lit: .white, track: .gray)
        let full = Glyph.ring(percent: 100, lit: .white, track: .gray)
        let whiteCount: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter { $0.on && $0.color == .white }.count
        }
        #expect(whiteCount(empty) == 0)
        #expect(whiteCount(full) > 20)
        // The ring's shape (lit plus track cells) is constant regardless of utilization.
        let ringCells: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter(\.on).count
        }
        #expect(ringCells(empty) == ringCells(full))
        // Lighting starts at 12 o'clock (straight up).
        #expect(Glyph.ring(percent: 5, lit: .white, track: .gray).cell(row: 1, col: 6).color == .white)
    }

    @Test("RING SPINNER moves its arc with phase while keeping RING's ring shape")
    func ringSpinnerRotates() {
        let atTop = Glyph.ringSpinner(phase: 0, lit: .white, track: .gray)
        let quarter = Glyph.ringSpinner(phase: 0.25, lit: .white, track: .gray)

        // The set of ring cells matches RING, so the shape does not jump when loading
        // resolves into a value.
        let onCells: (GlyphBitmap) -> Set<Int> = { bitmap in
            Set(
                (0..<bitmap.rows).flatMap { row in
                    (0..<bitmap.cols).compactMap { col in
                        bitmap.cell(row: row, col: col).on ? row * bitmap.cols + col : nil
                    }
                }
            )
        }
        #expect(onCells(atTop) == onCells(Glyph.ring(percent: 50, lit: .white, track: .gray)))
        #expect(onCells(atTop) == onCells(quarter))

        // The arc head sits at 12 o'clock at phase 0 and 3 o'clock at 0.25 (clockwise).
        #expect(atTop.cell(row: 1, col: 6).color != .gray)
        #expect(quarter.cell(row: 6, col: 11).color != .gray)
        // A different phase changes the color distribution, which is what makes it spin.
        let colors: (GlyphBitmap) -> [String] = { bitmap in
            (0..<bitmap.rows).flatMap { row in
                (0..<bitmap.cols).map {
                    "\(bitmap.cell(row: row, col: $0).color.map(String.init(describing:)) ?? "-")"
                }
            }
        }
        #expect(colors(atTop) != colors(quarter))

        // The arc covers only part of the ring; it never lights the full circle.
        let litCount: (GlyphBitmap) -> Int = { bitmap in
            (0..<bitmap.rows).flatMap { row in (0..<bitmap.cols).map { bitmap.cell(row: row, col: $0) } }
                .filter { $0.on && $0.color != .gray }.count
        }
        #expect(litCount(atTop) > 0)
        #expect(litCount(atTop) < onCells(atTop).count)

        // Out-of-range phases wrap around: 1.0 renders the same figure as 0.0.
        #expect(colors(Glyph.ringSpinner(phase: 1, lit: .white, track: .gray)) == colors(atTop))
    }

    // MARK: - B / C / D

    @Test("TASK reads as stages: outline, then outline plus core, then filled")
    func taskGlyphsEscalate() {
        #expect(ascii(Glyph.task(.todo)) == ["#####", "#...#", "#...#", "#...#", "#####"])
        #expect(ascii(Glyph.task(.active)) == ["#####", "#...#", "#.#.#", "#...#", "#####"])
        #expect(ascii(Glyph.task(.done)) == ["#####", "#####", "#####", "#####", "#####"])
    }

    @Test("SUBAGENT's diamond and MEMBER's block are distinguishable by shape")
    func subagentAndMemberDiffer() {
        #expect(ascii(Glyph.subagentRunning()) == ["..#..", ".###.", "#####", ".###.", "..#.."])
        #expect(ascii(Glyph.subagentIdle()) == ["..#..", ".#.#.", "#...#", ".#.#.", "..#.."])
        // A mock circle collapses into the same diamond at 5x5, so teammate uses a solid
        // 3x3 block in the center instead.
        #expect(ascii(Glyph.member()) == [".....", ".###.", ".###.", ".###.", "....."])
        #expect(ascii(Glyph.member()) != ascii(Glyph.subagentRunning()))
        #expect(ascii(Glyph.member()) != ascii(Glyph.task(.done)))
    }

    @Test("USAGE blocks convey headroom through filled versus outlined shapes")
    func usageBlockShowsFillState() {
        #expect(ascii(Glyph.usageBlock(filled: true, color: .white)) == ["###", "###", "###"])
        #expect(ascii(Glyph.usageBlock(filled: false, color: .white)) == ["###", "#.#", "###"])
    }

    // MARK: - E · NUMERIC

    @Test("NUMERIC glyphs are 5x7 with a one-cell gap between characters")
    func numericIsFiveBySevenWithGap() {
        let single = Glyph.number("1")
        #expect(single.rows == 7)
        #expect(single.cols == 5)

        let double = Glyph.number("62")
        // 5 + 1 (gap) + 5 = 11
        #expect(double.cols == 11)
        // The gap column is entirely empty.
        #expect((0..<double.rows).allSatisfy { !double.cell(row: $0, col: 5).on })
    }

    @Test("n/m can color the numerator and denominator differently")
    func numericSupportsPerCharacterColor() {
        let fraction = Glyph.number("3/7") { index in index == 0 ? .white : .gray }
        let numerator = (0..<fraction.rows).compactMap { fraction.cell(row: $0, col: 0).color }
        #expect(numerator.allSatisfy { $0 == .white })
    }

    @Test("FRAMED centers its digits inside the 13x13 frame")
    func framedNumberCentersInStateGrid() {
        let framed = Glyph.framedNumber("62")
        #expect(framed.rows == 13)
        #expect(framed.cols == 13)
        // The top and bottom 3 rows are empty framing margin.
        #expect((0..<framed.cols).allSatisfy { !framed.cell(row: 0, col: $0).on })
        #expect((0..<framed.cols).allSatisfy { !framed.cell(row: 12, col: $0).on })
        // There are lit cells near the center.
        #expect((0..<framed.cols).contains { framed.cell(row: 6, col: $0).on })
    }

    // MARK: - F · DOZING

    /// The sleeping face shown in the empty state. The face (outline, eyes, mouth) is
    /// always drawn regardless of phase; only the zzz count grows. A missing face would
    /// read as "broken" rather than "nothing here".
    @Test("DOZING always draws the face; only the zzz count grows with phase")
    func dozingKeepsFaceAndGrowsZs() {
        let rest = Glyph.dozing(phase: 0.0)
        let full = Glyph.dozing(phase: 0.9)

        #expect(rest.rows == Glyph.stateSize)
        #expect(rest.cols == Glyph.dozingCols)

        // The face (the left 13 columns) is identical at every phase.
        func faceRows(_ bitmap: GlyphBitmap) -> [String] {
            (0..<bitmap.rows).map { row in
                (0..<Glyph.stateSize).map { bitmap.cell(row: row, col: $0).on ? "#" : "." }.joined()
            }
        }
        #expect(faceRows(rest) == faceRows(full))

        // Closed eyes (two horizontal bars) and a smiling mouth are present.
        #expect(rest.cell(row: 5, col: 3).on && rest.cell(row: 5, col: 4).on)
        #expect(rest.cell(row: 5, col: 8).on && rest.cell(row: 5, col: 9).on)
        #expect(rest.cell(row: 9, col: 6).on)
        // The mouth corners sit one cell above its center (`‿`).
        #expect(rest.cell(row: 8, col: 4).on && rest.cell(row: 8, col: 8).on)
    }

    /// The zzz cycle rests on beat 0 of 4, then climbs 1, 2, 3.
    @Test("DOZING's zzz count grows from 0 to 3 across the phase")
    func dozingZCountFollowsPhase() {
        func zCount(_ phase: Double) -> Int {
            let bitmap = Glyph.dozing(phase: phase)
            // Count only the top-left cell of each 3x3 z, its origin.
            return [(14, 8), (16, 4), (18, 0)].count { bitmap.cell(row: $0.1, col: $0.0).on }
        }
        #expect(zCount(0.0) == 0)
        #expect(zCount(0.3) == 1)
        #expect(zCount(0.55) == 2)
        #expect(zCount(0.9) == 3)
        // A phase of 1.0 must not index outside the array.
        #expect(zCount(1.0) == 3)
    }

    /// The face outline reuses the usage gauge's ring. Independent radii would produce
    /// two subtly different circles inside the same 13x13 grid.
    @Test("DOZING's outline is the same circle as the usage ring")
    func dozingReusesUsageRing() {
        let bitmap = Glyph.dozing(phase: 0)
        for index in Glyph.ringCellIndices {
            #expect(bitmap.cell(row: index / Glyph.stateSize, col: index % Glyph.stateSize).on)
        }
    }
}
