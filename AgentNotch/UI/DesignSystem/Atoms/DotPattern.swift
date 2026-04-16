import SwiftUI

/// セッションの状態を 15×15 ドットマトリクスで表現するためのパターン定義。
///
/// 形として区別可能なので、色が消えても状態が読める（ある種のアクセシビリティ）。
/// 各 case は `signalColor` で意味色を持つが、UI 側は「形 × 色」の両方で判別できる。
enum DotPattern: Hashable {
    /// 呼吸する中央 1 点（idle / starting）
    case standby
    /// 1 列が左→右に流れる scan line（thinking / compacting）
    case thinking
    /// 左から段階的に埋まる bar、2 秒周期で 0→15 を循環（tool / subagent running）
    case working
    /// 点滅する `!`（permission waiting / ask question）
    case alert
    /// ランダム明滅する `×`（error / stop failure）
    case fault
    /// 静止する `✓`（done / completed）
    case complete

    /// 状態意味色。DotMatrix が use するが、呼び出し側が override も可。
    var signalColor: Color {
        switch self {
        case .standby: return DSColors.signalIdle
        case .thinking: return DSColors.signalThinking
        case .working: return DSColors.signalWorking
        case .alert: return DSColors.signalAlert
        case .fault: return DSColors.signalError
        case .complete: return DSColors.signalDone
        }
    }
}

/// 15×15 ドットマトリクスの bitmap 計算。
///
/// 時間 `t` に応じて loop パターンは動的に、静止パターンは fixed bitmap を返す。
/// `DotMatrix` が TimelineView から `ctx.date` を渡して毎フレーム評価する。
enum DotBitmap {
    static let cols = 15
    static let rows = 15

    /// 与えられたパターンを時刻 t（秒）で評価した bitmap を返す。
    static func grid(for pattern: DotPattern, time: TimeInterval) -> [[Bool]] {
        switch pattern {
        case .standby:
            return breathingCenter()
        case .thinking:
            return scanningColumn(time: time)
        case .working:
            return barFill(time: time)
        case .alert:
            return blinkExclamation(time: time)
        case .fault:
            return flickerCross(time: time)
        case .complete:
            return staticCheck()
        }
    }

    // MARK: - Pattern builders

    /// 中央 1 点。DotMatrix 側で opacity を 1.4s pulse させる想定で、bitmap は静止。
    private static func breathingCenter() -> [[Bool]] {
        parse("""
        ...............
        ...............
        ...............
        ...............
        ...............
        ...............
        ...............
        .......#.......
        ...............
        ...............
        ...............
        ...............
        ...............
        ...............
        ...............
        """)
    }

    /// 1.2s 周期で左→右に 1 列が移動する scan line。matrix 全 15 行を使う。
    private static func scanningColumn(time: TimeInterval) -> [[Bool]] {
        let period = 1.2
        let phase = time.truncatingRemainder(dividingBy: period) / period  // 0...1
        let col = Int(phase * Double(cols)) % cols
        var grid = emptyGrid()
        for r in 0..<rows {
            grid[r][col] = true
        }
        return grid
    }

    /// 2 秒周期で 0→15 を循環する横バー群（tool running 表現）。matrix 全 15 行を使う。
    private static func barFill(time: TimeInterval) -> [[Bool]] {
        let period = 2.0
        let phase = time.truncatingRemainder(dividingBy: period) / period   // 0...1
        let filled = min(cols, Int(phase * Double(cols + 1)))                // 0...cols
        var grid = emptyGrid()
        guard filled > 0 else { return grid }
        for r in 0..<rows {
            for c in 0..<filled {
                grid[r][c] = true
            }
        }
        return grid
    }

    /// `!` を 0.56s 周期で点滅。縦棒 9 行 + 空 2 行 + 点 1 行。
    private static func blinkExclamation(time: TimeInterval) -> [[Bool]] {
        let period = 0.56
        let on = time.truncatingRemainder(dividingBy: period) < period / 2
        if !on { return emptyGrid() }
        return parse("""
        ...............
        .......#.......
        .......#.......
        .......#.......
        .......#.......
        .......#.......
        .......#.......
        .......#.......
        .......#.......
        .......#.......
        ...............
        ...............
        .......#.......
        ...............
        ...............
        """)
    }

    /// `×` をランダム明滅。15×15 対角線 2 本。
    private static func flickerCross(time: TimeInterval) -> [[Bool]] {
        let step = Int((time / 0.08).rounded(.down))
        let on = abs(step.hashValue) % 10 < 7
        if !on { return emptyGrid() }
        return parse("""
        #.............#
        .#...........#.
        ..#.........#..
        ...#.......#...
        ....#.....#....
        .....#...#.....
        ......#.#......
        .......#.......
        ......#.#......
        .....#...#.....
        ....#.....#....
        ...#.......#...
        ..#.........#..
        .#...........#.
        #.............#
        """)
    }

    /// `✓` を静止表示。15×15 内で bounding box を中央寄せ（cols 3–12, rows 4–11）。
    private static func staticCheck() -> [[Bool]] {
        parse("""
        ...............
        ...............
        ...............
        ...............
        ............#..
        ...........#...
        ..........#....
        .........#.....
        ........#......
        ...#...#.......
        ....#.#........
        .....#.........
        ...............
        ...............
        ...............
        """)
    }

    // MARK: - Helpers

    private static func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: cols), count: rows)
    }

    /// `#` = on / `.` = off の 15 文字 × 15 行のテキストを bitmap にする。
    private static func parse(_ s: String) -> [[Bool]] {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        var grid = emptyGrid()
        for (r, line) in lines.prefix(rows).enumerated() {
            for (c, ch) in line.prefix(cols).enumerated() {
                grid[r][c] = (ch == "#")
            }
        }
        return grid
    }
}
