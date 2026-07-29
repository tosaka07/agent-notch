import SwiftUI

/// Agent Notch's glyph dictionary.
///
/// **No font characters (`□▪■` / `◆◇` / `●`).** Everything is drawn as dots on a grid.
/// The principle: the shape tells the state; color is secondary, and it stays readable
/// with the color gone.
///
/// | Class | Size | Use |
/// | --- | --- | --- |
/// | A · STATE | 13×13 | Session state (compact left wing / card left column) |
/// | B · TASK | 5×5 | Task todo / active / done |
/// | C · SUBAGENT / MEMBER | 5×5 | Subagent running / free slot, teammate |
/// | D · USAGE | 3×3 | One usage tick block (10 blocks = 100%) |
/// | E · NUMERIC | 5×7 | Numbers and `n/m` counters (3×5 and 4×5 are not used) |
enum Glyph {
    // MARK: - A · STATE 13×13

    static let stateSize = 13

    /// The state glyph figures. Animation is expressed through `phase` (0–1).
    ///
    /// For the motion spec (period / easing) see `StateGlyph.duration`.
    enum State: Equatable {
        /// idle / starting — a still ring
        case standby
        /// thinking / compacting — a waveform
        case thinking
        /// tool execution — a filled core
        case working
        /// n subagents in parallel — filling 9 slots
        case swarm(active: Int)
        /// awaiting approval — an exclamation mark
        case alert
        /// awaiting an answer — a question mark
        case question
        /// awaiting plan approval — three lines
        case planReview
        /// done — a check
        case complete
        /// error — an ×
        case fault

        /// Length of one animation cycle, in seconds. `loop == false` plays it only once.
        var duration: TimeInterval {
            switch self {
            case .standby: 2.4
            case .thinking: 1.6
            case .working: 0.9
            case .swarm: 0.12  // per slot
            case .alert: 1.0
            case .question: 1.0
            case .planReview: 1.0
            case .complete: 0.48
            case .fault: 0.32
            }
        }

        /// Whether it repeats. complete stops once it has finished drawing.
        var loops: Bool {
            switch self {
            case .complete, .swarm: false
            default: true
            }
        }
    }

    /// Evaluates a state glyph at phase `phase` (0–1).
    static func state(_ state: State, phase: Double = 0) -> GlyphBitmap {
        switch state {
        case .standby: standby(phase: phase)
        case .thinking: thinking(phase: phase)
        case .working: working(phase: phase)
        case .swarm(let active): swarm(active: active)
        case .alert: alert(phase: phase)
        case .question: question(phase: phase)
        case .planReview: planReview(phase: phase)
        case .complete: complete(progress: min(1, phase * 1.15))
        case .fault: fault(phase: phase)
        }
    }

    /// The ring breathes by one cell. **Only the radius moves; no dots are added or removed.**
    private static func standby(phase: Double) -> GlyphBitmap {
        let radius = 3.5 + 0.9 * sin(phase * 2 * .pi)
        return GlyphBitmap.square(stateSize, on: DSColors.signalIdle) { x, y in
            let d = distance(x, y)
            return d > radius - 0.75 && d < radius + 0.75
        }
    }

    /// Shifts a sine wave through one full phase. Rows always round to whole cells.
    private static func thinking(phase: Double) -> GlyphBitmap {
        GlyphBitmap.square(stateSize, on: DSColors.signalThinking) { x, y in
            let wave = 6 + 3 * sin((Double(x) / 12) * 2 * .pi - phase * 2 * .pi)
            return y == Int(wave.rounded())
        }
    }

    /// The core pulses between radius 2 and 4 cells. One beat per tool call.
    private static func working(phase: Double) -> GlyphBitmap {
        let radius = 2.2 + 1.6 * (0.5 - 0.5 * cos(phase * 2 * .pi))
        return GlyphBitmap.square(stateSize, on: DSColors.signalWorking) { x, y in
            distance(x, y) <= radius
        }
    }

    /// Nine 3×3 slots inside the 13×13. Lit count = parallel count, filled in launch order.
    private static func swarm(active: Int) -> GlyphBitmap {
        let clamped = max(1, min(9, active))
        let starts = [1, 5, 9]
        return GlyphBitmap.square(stateSize, on: DSColors.signalWorking) { x, y in
            guard let bx = starts.firstIndex(where: { x >= $0 && x <= $0 + 2 }),
                let by = starts.firstIndex(where: { y >= $0 && y <= $0 + 2 })
            else { return false }
            return by * 3 + bx < clamped
        }
    }

    /// An exclamation mark. Blink duty is 55/45, and **the off phase stays at 0.22**
    /// so the shape never disappears.
    private static func alert(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.55
        let color = lit ? DSColors.signalAlert : DSColors.signalAlert.opacity(0.22)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (x >= 5 && x <= 7 && y >= 2 && y <= 7) || (x >= 5 && x <= 7 && y >= 9 && y <= 10)
        }
    }

    /// A question mark. It shares ALERT's blink cadence because both states need attention,
    /// while the figure and warmer orange distinguish answering from granting permission.
    private static func question(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.55
        let color = lit ? DSColors.signalQuestion : DSColors.signalQuestion.opacity(0.22)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (y == 2 && x >= 4 && x <= 8)
                || (x >= 3 && x <= 4 && y >= 3 && y <= 4)
                || (x >= 8 && x <= 9 && y >= 3 && y <= 5)
                || (x >= 7 && x <= 8 && y >= 5 && y <= 6)
                || (x >= 5 && x <= 7 && y >= 6 && y <= 7)
                || (x >= 5 && x <= 6 && y >= 9 && y <= 10)
        }
    }

    /// Three lines (the body of a plan). Blinks on the same duty as alert, distinguished by color.
    private static func planReview(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.6
        let color = lit ? DSColors.signalPlan : DSColors.signalPlan.opacity(0.22)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (y == 3 && x >= 2 && x <= 10) || (y == 6 && x >= 2 && x <= 7) || (y == 9 && x >= 2 && x <= 10)
        }
    }

    /// Draws the check in from the lower left. Returning to standby 1.2s after it completes
    /// is the caller's responsibility.
    private static func complete(progress: Double) -> GlyphBitmap {
        var points: [(Int, Int)] = []
        for x in 2...5 { points.append((x, x + 4)) }
        for x in 6...10 { points.append((x, 14 - x)) }
        let count = Int((Double(points.count) * min(max(progress, 0), 1)).rounded())
        let visible = points.prefix(count)
        return GlyphBitmap.square(stateSize, on: DSColors.signalDone) { x, y in
            visible.contains { $0.0 == x && $0.1 == y }
        }
    }

    /// An ×, flickering finely to convey "something is broken".
    private static func fault(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.7
        let color = lit ? DSColors.signalError : DSColors.signalError.opacity(0.25)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (abs(x - y) <= 1 || abs(x + y - 12) <= 1) && x >= 2 && x <= 10 && y >= 2 && y <= 10
        }
    }

    private static func distance(_ x: Int, _ y: Int) -> Double {
        let dx = Double(x - 6)
        let dy = Double(y - 6)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - A' · RING 13×13 (the usage ring gauge)

    /// Indices of the cells forming the ring, ordered clockwise from 12 o'clock.
    ///
    /// `ring` and `ringSpinner` share the same ring — if only one changed shape, the ring would
    /// visibly jump at the loading → settled handoff. The grid size is fixed, so this is
    /// computed once.
    static let ringCellIndices: [Int] = {
        let center = 6.0
        let radius = 5.2
        var ordered: [(index: Int, angle: Double)] = []
        for y in 0..<stateSize {
            for x in 0..<stateSize {
                let dx = Double(x) - center
                let dy = Double(y) - center
                let d = (dx * dx + dy * dy).squareRoot()
                guard d > radius - 0.75, d < radius + 0.75 else { continue }
                var angle = atan2(Double(x) - center, center - Double(y)) * 180 / .pi
                if angle < 0 { angle += 360 }
                ordered.append((y * stateSize + x, angle))
            }
        }
        return ordered.sorted { $0.angle < $1.angle }.map(\.index)
    }()

    /// A ring on the 13×13 grid, lit in angular order up to `percent`.
    /// Unlit cells use `track` (a faint agent color, used for identification).
    static func ring(percent: Double, lit: Color, track: Color) -> GlyphBitmap {
        let indices = ringCellIndices
        let clamped = min(max(percent, 0), 100) / 100
        var colorByIndex: [Int: Color] = [:]
        for (k, index) in indices.enumerated() {
            let ratio = Double(k) / Double(indices.count)
            colorByIndex[index] = ratio < clamped - 1e-9 ? lit : track
        }
        return ringBitmap(colorByIndex: colorByIndex)
    }

    /// The ring while loading. Instead of a value, **an arc keeps going around** to say
    /// "still fetching".
    ///
    /// A 0% ring shown before the value settles is misread as "zero usage", so it is replaced
    /// by motion that cannot be read as a number. The arc is densest at its head and fades
    /// toward the tail, so the direction of travel is legible from shape alone (upholding the
    /// principle that it stays readable with the color gone).
    ///
    /// - Parameters:
    ///   - phase: Phase from 0 to 1; 1 is one revolution. Values outside wrap around.
    ///   - arcRatio: Arc length, as a fraction of the whole ring.
    static func ringSpinner(
        phase: Double,
        arcRatio: Double = 0.3,
        lit: Color,
        track: Color
    ) -> GlyphBitmap {
        let indices = ringCellIndices
        let count = indices.count
        guard count > 0 else { return ringBitmap(colorByIndex: [:]) }

        var colorByIndex: [Int: Color] = [:]
        for index in indices { colorByIndex[index] = track }

        let wrapped = phase - phase.rounded(.down)
        let head = min(count - 1, Int(wrapped * Double(count)))
        let arcCount = min(count, max(2, Int((Double(count) * arcRatio).rounded())))
        for k in 0..<arcCount {
            // The tail extends behind the head (opposite the direction of travel).
            let position = ((head - k) % count + count) % count
            let fade = 1 - Double(k) / Double(arcCount)
            colorByIndex[indices[position]] = lit.opacity(0.25 + 0.75 * fade)
        }
        return ringBitmap(colorByIndex: colorByIndex)
    }

    /// Builds a 13×13 bitmap from the ring's cell-color map. Cells outside the ring stay off.
    private static func ringBitmap(colorByIndex: [Int: Color]) -> GlyphBitmap {
        var cells: [[DotCell]] = []
        for y in 0..<stateSize {
            var row: [DotCell] = []
            for x in 0..<stateSize {
                if let color = colorByIndex[y * stateSize + x] {
                    row.append(.on(color: color))
                } else {
                    row.append(.off)
                }
            }
            cells.append(row)
        }
        return GlyphBitmap(rows: stateSize, cols: stateSize, cells: cells)
    }

    // MARK: - B · TASK 5×5

    /// Task state. todo = outline only / active = outline + core / done = filled.
    enum TaskGlyph { case todo, active, done }

    static func task(_ glyph: TaskGlyph, color: Color? = nil) -> GlyphBitmap {
        switch glyph {
        case .todo:
            GlyphBitmap.square(5, on: color ?? DSColors.inkDim) { x, y in
                x == 0 || y == 0 || x == 4 || y == 4
            }
        case .active:
            GlyphBitmap.square(5, on: color ?? DSColors.ink.opacity(0.7)) { x, y in
                x == 0 || y == 0 || x == 4 || y == 4 || (x == 2 && y == 2)
            }
        case .done:
            GlyphBitmap.square(5, on: color ?? DSColors.ink.opacity(0.7)) { _, _ in true }
        }
    }

    // MARK: - C · SUBAGENT / MEMBER 5×5

    /// Subagent running — a filled diamond.
    static func subagentRunning(color: Color = DSColors.signalWorking) -> GlyphBitmap {
        GlyphBitmap.square(5, on: color) { x, y in abs(x - 2) + abs(y - 2) <= 2 }
    }

    /// A free subagent slot — a diamond outline.
    static func subagentIdle(color: Color = DSColors.inkMute) -> GlyphBitmap {
        GlyphBitmap.square(5, on: color) { x, y in abs(x - 2) + abs(y - 2) == 2 }
    }

    /// Teammate — a solid 3×3 block at the center.
    ///
    /// A circle would be the obvious choice, but on a 5×5 grid a radius-2.1 circle and the
    /// diamond (`subagentRunning`) come out as **exactly the same shape** (the corners drop and
    /// the cross plus diagonals fill in). That violates "the shape tells the state", so teammate
    /// is a center 3×3 block, distinguishable from the diamond (subagent), the diamond outline
    /// (free slot), and the full fill (task done).
    static func member(color: Color = DSColors.inkDim) -> GlyphBitmap {
        GlyphBitmap.square(5, on: color) { x, y in
            x >= 1 && x <= 3 && y >= 1 && y <= 3
        }
    }

    // MARK: - D · USAGE 3×3 block

    /// One usage tick block. Ten of them make 100%.
    ///
    /// Consumed = filled, remaining = outline. **Severity changes only the color, never the
    /// ticks (block count)**, so API-provided severity and our own thresholds ride the same scale.
    ///
    /// The center of an outline block is returned as "off". To show it faintly, pass a color to
    /// `GlyphView(ghost:)` — the lit/unlit meaning does not belong in the bitmap.
    static func usageBlock(filled: Bool, color: Color) -> GlyphBitmap {
        GlyphBitmap.square(3, on: filled ? color : color.opacity(0.5)) { x, y in
            filled || x == 0 || y == 0 || x == 2 || y == 2
        }
    }

    // MARK: - F · DOZING 20×13 (the empty state, when there is no session at all)

    /// Width of one empty-state glyph, in cells. Face 13 + gap 1 + zzz 7.
    static let dozingCols = 21

    /// Expresses "nobody is awake" with a sleeping face and rising zzz.
    ///
    /// The empty state is not an error, so no negative figure like `fault` is used. Text alone
    /// would not do either: every other screen speaks in dots, and **this one place would fall
    /// back to language**. The face goes on the same 13×13 grid as the state glyphs, with zzz
    /// stacking to its right, so emptiness reads as "waiting quietly".
    ///
    /// The zzz build up from the bottom and grow fainter toward the top (as if dissolving into
    /// the air). At phase 0 none are shown, so there is a breath before they start rising again.
    /// Like every other glyph, the dots stay on the grid — no sub-pixel movement.
    static func dozing(phase: Double) -> GlyphBitmap {
        // Beat 0 of 4 is a rest. Then they rise 1 → 2 → 3.
        let litCount = Int((min(max(phase, 0), 0.999) * 4).rounded(.down))

        var cells = Array(
            repeating: Array(repeating: DotCell.off, count: dozingCols),
            count: stateSize
        )
        func light(_ x: Int, _ y: Int, _ color: Color) {
            guard y >= 0, y < stateSize, x >= 0, x < dozingCols else { return }
            cells[y][x] = .on(color: color)
        }

        let face = DSColors.signalIdle
        // The face outline. **Without it the eyes and mouth are just scattered dots**, so the
        // ring at standby's radius says "this is a face" first.
        // The circle reuses the usage gauge's `ringCellIndices`; picking a radius here would
        // create two subtly different circles inside the same 13×13.
        for index in ringCellIndices {
            light(index % stateSize, index / stateSize, face)
        }
        // Closed eyes: two 2-cell horizontal bars. The eye shape alone conveys sleep.
        for (x, y) in [(3, 5), (4, 5), (8, 5), (9, 5)] { light(x, y, face) }
        // A smiling mouth (`‿`). Raising just the two ends by one cell lifts the corners.
        for (x, y) in [(4, 8), (5, 9), (6, 9), (7, 9), (8, 8)] { light(x, y, face) }

        // zzz: three 3×3 z's going up-right. Lower-left is newest, upper-right older and fainter.
        let zOrigins = [(14, 8), (16, 4), (18, 0)]
        let opacities = [1.0, 0.55, 0.3]
        for index in 0..<litCount {
            let (ox, oy) = zOrigins[index]
            let color = face.opacity(opacities[index])
            // Top and bottom bars plus a diagonal center: the smallest form still readable
            // as a z at 3×3.
            for dx in 0...2 {
                light(ox + dx, oy, color)
                light(ox + dx, oy + 2, color)
            }
            light(ox + 1, oy + 1, color)
        }

        return GlyphBitmap(rows: stateSize, cols: dozingCols, cells: cells)
    }

    // MARK: - E · NUMERIC 5×7

    /// The 5×7 bitmap font. Numbers, `n/m`, `%`, and `$` are all written with this one face.
    private static let font7: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "%": ["10001", "00010", "00100", "01000", "10001", "00000", "00000"],
        "$": ["00100", "01111", "10100", "01110", "00101", "11110", "00100"],
        "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
        " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    ]

    static let numericRows = 7
    /// Width per character (5 cells + 1 cell of tracking).
    private static let numericStride = 6

    /// Draws a string in 5×7 dots. Color can vary per character (e.g. dimming the
    /// denominator of `n/m`).
    static func number(_ text: String, colorForCharacter: (Int) -> Color) -> GlyphBitmap {
        let characters = Array(text)
        guard !characters.isEmpty else { return .empty(rows: numericRows, cols: 0) }
        let cols = characters.count * numericStride - 1

        var cells: [[DotCell]] = []
        for y in 0..<numericRows {
            var row: [DotCell] = []
            for x in 0..<cols {
                let charIndex = x / numericStride
                let column = x % numericStride
                var lit = false
                // The tracking column (the 6th) is always left blank.
                if column < 5, let glyph = font7[characters[charIndex]] {
                    let bits = Array(glyph[y])
                    lit = column < bits.count && bits[column] == "1"
                }
                row.append(lit ? .on(color: colorForCharacter(charIndex)) : .off)
            }
            cells.append(row)
        }
        return GlyphBitmap(rows: numericRows, cols: cols, cells: cells)
    }

    static func number(_ text: String, color: Color = DSColors.ink) -> GlyphBitmap {
        number(text) { _ in color }
    }

    /// Fits 5×7 digits into the same 13×13 frame as the state glyphs (a framed number).
    static func framedNumber(_ text: String, color: Color = DSColors.ink) -> GlyphBitmap {
        let inner = number(text, color: color)
        let offsetX = Int(((Double(stateSize) - Double(inner.cols)) / 2).rounded())
        let offsetY = Int(((Double(stateSize) - Double(numericRows)) / 2).rounded())

        var cells = GlyphBitmap.empty(rows: stateSize, cols: stateSize).cells
        for y in 0..<inner.rows {
            for x in 0..<inner.cols {
                let ty = y + offsetY
                let tx = x + offsetX
                guard ty >= 0, ty < stateSize, tx >= 0, tx < stateSize else { continue }
                cells[ty][tx] = inner.cell(row: y, col: x)
            }
        }
        return GlyphBitmap(rows: stateSize, cols: stateSize, cells: cells)
    }
}
