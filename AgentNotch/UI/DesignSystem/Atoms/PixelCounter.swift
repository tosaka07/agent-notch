import SwiftUI

/// 13×13 正方形の中に "running / total" の 2 段カウンタを描画する atom。
///
/// # レイアウト（13×13、4×5 digit 2 段）
/// ```
/// rows 1–5:   running 2 桁 (tens cols 2–5, ones cols 7–10) — valueColor
/// row 6:      (空行)
/// rows 7–11:  total 2 桁 (同レイアウト) — totalColor
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
        var cells = DotBitmap.emptyCellGrid()
        drawTwoDigit(max(0, min(99, value)), rowOffset: 1, color: valueColor, into: &cells)
        drawTwoDigit(max(0, min(99, total)), rowOffset: 7, color: totalColor, into: &cells)
        return cells
    }

    private static func drawTwoDigit(
        _ n: Int, rowOffset: Int, color: Color, into cells: inout [[DotCell]]
    ) {
        let tens = digitBitmaps[(n / 10) % 10]
        let ones = digitBitmaps[n % 10]
        for r in 0..<5 {
            let tr = r + rowOffset
            guard tr < PixelGrid.dimension else { continue }
            for c in 0..<4 {
                if tens[r][c] { cells[tr][c + 2] = .on(color: color) }
                if ones[r][c] { cells[tr][c + 7] = .on(color: color) }
            }
        }
    }

    /// 4×5 digit bitmap のルックアップテーブル（static let でキャッシュ）。
    private static let digitBitmaps: [[[Bool]]] = (0...9).map { digit in
        let pattern: String = switch digit {
        case 0: ".##.\n#..#\n#..#\n#..#\n.##."
        case 1: "..#.\n.##.\n..#.\n..#.\n.###"
        case 2: ".##.\n...#\n.##.\n#...\n####"
        case 3: ".##.\n...#\n.##.\n...#\n.##."
        case 4: "#.#.\n#.#.\n####\n..#.\n..#."
        case 5: "####\n#...\n###.\n...#\n.##."
        case 6: ".##.\n#...\n###.\n#..#\n.##."
        case 7: "####\n..#.\n.#..\n#...\n#..."
        case 8: ".##.\n#..#\n.##.\n#..#\n.##."
        case 9: ".##.\n#..#\n.###\n...#\n.##."
        default: "....\n....\n....\n....\n...."
        }
        return pattern.split(separator: "\n").map { line in
            line.prefix(4).map { $0 == "#" }
        }
    }
}
