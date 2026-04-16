import SwiftUI

/// 15×15 正方形の中に "running / total" の 2 段カウンタを描画する atom。
///
/// 描画は `PixelGrid` に委譲。DotMatrix と完全に同じ手法で描かれる。
///
/// # レイアウト（15×15、5×7 digit 2 段）
/// ```
/// rows 0–6:   running 2 桁 (tens cols 2–6, ones cols 8–12) — 5×7 digit × 2 — valueColor
/// row 7:      (空行で区切り)
/// rows 8–14:  total 2 桁 (同レイアウト) — totalColor
/// ```
struct PixelCounter: View {
    let value: Int
    let total: Int
    var cellSize: CGFloat = 1.6
    var valueColor: Color = DSColors.ink
    var totalColor: Color = DSColors.inkDim

    var body: some View {
        PixelGrid(
            cells: Self.cells(value: value, total: total, valueColor: valueColor, totalColor: totalColor),
            cellSize: cellSize
        )
    }

    static func cells(value: Int, total: Int, valueColor: Color, totalColor: Color) -> [[DotCell]] {
        let dim = PixelGrid.dimension  // 15
        var cells = Array(repeating: Array(repeating: DotCell.off, count: dim), count: dim)

        let running = max(0, min(99, value))
        let totalClamped = max(0, min(99, total))

        drawTwoDigit(running, rowOffset: 0, color: valueColor, into: &cells)
        drawTwoDigit(totalClamped, rowOffset: 8, color: totalColor, into: &cells)

        return cells
    }

    private static func drawTwoDigit(
        _ n: Int,
        rowOffset: Int,
        color: Color,
        into cells: inout [[DotCell]]
    ) {
        let tens = (n / 10) % 10
        let ones = n % 10
        let tensBits = bitmap5x7(for: tens)
        let onesBits = bitmap5x7(for: ones)
        for r in 0..<7 {
            for c in 0..<5 {
                if tensBits[r][c] {
                    cells[r + rowOffset][c + 2] = .on(color: color)  // tens: cols 2-6
                }
                if onesBits[r][c] {
                    cells[r + rowOffset][c + 8] = .on(color: color)  // ones: cols 8-12
                }
            }
        }
    }

    /// 5×7 の classic LCD 風 pixel digit。0-9 を区別可能。
    private static func bitmap5x7(for digit: Int) -> [[Bool]] {
        let pattern: String = switch digit {
        case 0: ".###.\n#...#\n#...#\n#...#\n#...#\n#...#\n.###."
        case 1: "..#..\n.##..\n..#..\n..#..\n..#..\n..#..\n.###."
        case 2: ".###.\n#...#\n....#\n...#.\n..#..\n.#...\n#####"
        case 3: ".###.\n#...#\n....#\n..##.\n....#\n#...#\n.###."
        case 4: "...#.\n..##.\n.#.#.\n#..#.\n#####\n...#.\n...#."
        case 5: "#####\n#....\n####.\n....#\n....#\n#...#\n.###."
        case 6: ".###.\n#....\n#....\n####.\n#...#\n#...#\n.###."
        case 7: "#####\n....#\n...#.\n..#..\n.#...\n.#...\n.#..."
        case 8: ".###.\n#...#\n#...#\n.###.\n#...#\n#...#\n.###."
        case 9: ".###.\n#...#\n#...#\n.####\n....#\n....#\n.###."
        default: ".....\n.....\n.....\n.....\n.....\n.....\n....."
        }
        return parse5x7(pattern)
    }

    private static func parse5x7(_ s: String) -> [[Bool]] {
        s.split(separator: "\n").map { line in
            line.prefix(5).map { $0 == "#" }
        }
    }
}
