import SwiftUI

/// セッションの状態を 13×13 ドットマトリクスで表現するためのパターン定義。
///
/// 形として区別可能なので、色が消えても状態が読める（ある種のアクセシビリティ）。
/// 各 case は `signalColor` で意味色を持つが、UI 側は「形 × 色」の両方で判別できる。
enum DotPattern: Hashable {
    case standby
    case thinking
    case working
    case alert
    case fault
    case complete
    /// 並行実行中の subagent 数（1–9 に clamp）を 2×2 ブロックの脈動で表現する。
    case swarm(active: Int)
    /// Plan モード終了確認（`ExitPlanMode` の承認待ち）。書類（横線 3 本）の形で alert と区別する。
    case planReview

    var signalColor: Color {
        switch self {
        case .standby: return DSColors.signalIdle
        case .thinking: return DSColors.signalThinking
        case .working: return DSColors.signalWorking
        case .alert: return DSColors.signalAlert
        case .fault: return DSColors.signalError
        case .complete: return DSColors.signalDone
        case .swarm: return DSColors.signalWorking
        case .planReview: return DSColors.signalPlan
        }
    }

    /// `TimelineView` の最小 tick 間隔（秒）。
    ///
    /// 各パターンの実際の状態変化周期に基づく。`nil` は現状通り毎フレーム
    /// （`TimelineView(.animation)`）で評価する必要があるパターン
    /// （complete のフェード、swarm の sin 脈動など「見た目のなめらかさ」が要件のもの）。
    ///
    /// それ以外は on/off の離散的な切り替えか、13 分割程度の粗いステップでしか
    /// 見た目が変わらないため、60fps+ で再評価しても無駄になる。以下は各パターンの
    /// 実測周期から導出した間隔（değişim frequency 以下に絞ることで cellGrid 再計算・
    /// View 再構築の回数を 1/4〜1/7 程度に削減できる）:
    /// - `.standby`: 呼吸 opacity は sin 周期 1.4s。cellGrid 自体は不変（bitmap 固定）で
    ///   opacity の見た目だけが変化するため 10fps 相当（0.1s）でも滑らかに見える
    /// - `.thinking`: scanningColumn は 1.2s / 13 コマ ≈ 0.092s 間隔でしか列が動かない
    /// - `.working`: barFill は 2.0s / 14 コマ ≈ 0.143s 間隔でしか埋まらない
    /// - `.alert`: blink 周期 0.56s（on 0.28s / off 0.28s）
    /// - `.fault`: flicker は 0.08s 刻みの hash 判定
    /// - `.planReview`: blink 周期 1.0s（on 0.6s / off 0.4s）
    var minimumTickInterval: TimeInterval? {
        switch self {
        case .standby: return 0.1
        case .thinking: return 0.1
        case .working: return 0.15
        case .alert: return 0.2
        case .fault: return 0.08
        case .planReview: return 0.2
        case .complete, .swarm: return nil
        }
    }
}

/// 13×13 ドットマトリクスの bitmap 計算。
///
/// 全パターンを `[[DotCell]]` で統一的に返す。
/// complete パターンのみ opacity 付き DotCell を使い、それ以外は on/off + signalColor。
enum DotBitmap {
    static let cols = 13
    static let rows = 13

    /// 与えられたパターンを時刻 t（秒）で評価した `[[DotCell]]` を返す。
    static func cellGrid(for pattern: DotPattern, time: TimeInterval, signalColor: Color) -> [[DotCell]] {
        switch pattern {
        case .complete:
            return completeAnimation(time: time, color: signalColor)
        case .swarm(let active):
            return swarmAnimation(time: time, active: active, color: signalColor)
        default:
            return boolGrid(for: pattern, time: time).toCells(onColor: signalColor)
        }
    }

    // MARK: - Bool grid builders (complete / swarm 以外)

    private static func boolGrid(for pattern: DotPattern, time: TimeInterval) -> [[Bool]] {
        switch pattern {
        case .standby: breathingCenter
        case .thinking: scanningColumn(time: time)
        case .working: barFill(time: time)
        case .alert: blinkExclamation(time: time)
        case .fault: flickerCross(time: time)
        case .planReview: blinkPlanDocument(time: time)
        case .complete: smileyFull // unreachable, but required for exhaustive switch
        case .swarm: smileyFull // unreachable, cellGrid が先に処理する
        }
    }

    // MARK: - Static bitmaps (static let でキャッシュ)

    private static let breathingCenter: [[Bool]] = parse("""
    .............
    .............
    .............
    .............
    .............
    .....##......
    .....##......
    .............
    .............
    .............
    .............
    .............
    .............
    """)

    private static let exclamation: [[Bool]] = parse("""
    .............
    .....##......
    .....##......
    .....##......
    .....##......
    .....##......
    .....##......
    .....##......
    .............
    .............
    .....##......
    .....##......
    .............
    """)

    private static let cross: [[Bool]] = parse("""
    ##.........##
    .##.......##.
    ..##.....##..
    ...##...##...
    ....##.##....
    .....###.....
    ......#......
    .....###.....
    ....##.##....
    ...##...##...
    ..##.....##..
    .##.......##.
    ##.........##
    """)

    /// 塗りつぶし円 + 2×2 の目。
    private static let smileyFill: [[Bool]] = parse("""
    .............
    .............
    ....#####....
    ...#######...
    ..#..###..#..
    ..#..###..#..
    ..#########..
    ..#########..
    ..#########..
    ...#######...
    ....#####....
    .............
    .............
    """)

    /// 口の穴を含む完成形（static let でキャッシュ）。
    private static let smileyFull: [[Bool]] = {
        var grid = smileyFill
        for (r, c) in mouthDots {
            grid[r][c] = false
        }
        return grid
    }()

    /// 書類（横線 3 本 = plan テキストのイメージ）。alert（`!`）とは形状で明確に区別できる。
    private static let planDocument: [[Bool]] = parse("""
    .............
    .............
    ...#######...
    ...#.....#...
    ...#.###.#...
    ...#.....#...
    ...#.###.#...
    ...#.....#...
    ...#.###.#...
    ...#.....#...
    ...#######...
    .............
    .............
    """)

    private static let prompt: [[Bool]] = parse("""
    .............
    .............
    .............
    .##..........
    ..##.........
    ...##........
    ....##.......
    ...##........
    ..##.........
    .##..........
    .............
    .............
    .............
    """)

    // MARK: - Mouth dots (書き順: 左口角→底→右口角)

    /// 口の穴（書き順: 左口角 → 底 → 右口角）。口角が上がるスマイル。
    private static let mouthDots: [(Int, Int)] = [
        (7, 4), (8, 5), (8, 6), (8, 7), (7, 8),
    ]

    // MARK: - Cursor constants

    private static let cursorCol1 = 10
    private static let cursorCol2 = 11
    private static let cursorTop = 2
    private static let cursorBottom = 10
    private static let cursorPeriod = 1.6

    // MARK: - Complete animation timeline

    private static let smileyFadeDuration = 0.8
    private static let mouthDelay = 0.6
    private static let mouthFadeDuration = 0.5
    private static let smileyHoldDuration = 5.0
    private static let transitionDuration = 0.8

    private static let smileyPhaseEnd = smileyFadeDuration
    private static let holdPhaseEnd = smileyPhaseEnd + smileyHoldDuration
    private static let transPhaseEnd = holdPhaseEnd + transitionDuration

    // MARK: - Dynamic pattern builders

    private static func scanningColumn(time: TimeInterval) -> [[Bool]] {
        let phase = time.truncatingRemainder(dividingBy: 1.2) / 1.2
        let col = Int(phase * Double(cols)) % cols
        var grid = emptyGrid()
        for r in 0..<rows {
            grid[r][col] = true
            grid[r][(col + 1) % cols] = true
        }
        return grid
    }

    private static func barFill(time: TimeInterval) -> [[Bool]] {
        let phase = time.truncatingRemainder(dividingBy: 2.0) / 2.0
        let filled = min(cols, Int(phase * Double(cols + 1)))
        guard filled > 0 else { return emptyGrid() }
        var grid = emptyGrid()
        for r in 0..<rows {
            for c in 0..<filled { grid[r][c] = true }
        }
        return grid
    }

    private static func blinkExclamation(time: TimeInterval) -> [[Bool]] {
        time.truncatingRemainder(dividingBy: 0.56) < 0.28 ? exclamation : emptyGrid()
    }

    /// alert よりゆったりした周期で点滅させ、リズムでも alert と区別できるようにする。
    private static func blinkPlanDocument(time: TimeInterval) -> [[Bool]] {
        time.truncatingRemainder(dividingBy: 1.0) < 0.6 ? planDocument : emptyGrid()
    }

    private static func flickerCross(time: TimeInterval) -> [[Bool]] {
        let step = Int((time / 0.08).rounded(.down))
        return abs(step.hashValue) % 10 < 7 ? cross : emptyGrid()
    }

    // MARK: - Complete animation (DotCell 版)

    private static func completeAnimation(time: TimeInterval, color: Color) -> [[DotCell]] {
        if time < smileyPhaseEnd {
            return completePhaseSmileyFadeIn(time: time, color: color)
        } else if time < holdPhaseEnd {
            return smileyFull.toCells(onColor: color)
        } else if time < transPhaseEnd {
            return completePhaseTransition(time: time, color: color)
        } else {
            return completePhasePrompt(time: time, color: color)
        }
    }

    /// Phase 1: 本体フェードイン + 口を左から順に彫る
    private static func completePhaseSmileyFadeIn(time: TimeInterval, color: Color) -> [[DotCell]] {
        let bodyOpacity = min(1.0, time / smileyFadeDuration)
        let mouthTime = time - mouthDelay

        var cells = emptyCellGrid()
        for r in 0..<min(rows, smileyFill.count) {
            for c in 0..<min(cols, smileyFill[r].count) where smileyFill[r][c] {
                cells[r][c] = .on(color: color.opacity(bodyOpacity))
            }
        }
        if mouthTime > 0 {
            let visible = min(mouthDots.count, Int(mouthTime / mouthFadeDuration * Double(mouthDots.count)) + 1)
            for i in 0..<visible {
                let (r, c) = mouthDots[i]
                cells[r][c] = .off
            }
        }
        return cells
    }

    /// Phase 3: にこちゃん fade out + ">" fade in
    private static func completePhaseTransition(time: TimeInterval, color: Color) -> [[DotCell]] {
        let progress = (time - holdPhaseEnd) / transitionDuration
        var cells = emptyCellGrid()
        for r in 0..<rows {
            for c in 0..<cols {
                if smileyFill[r][c] {
                    cells[r][c] = .on(color: color.opacity(1.0 - progress))
                }
                if prompt[r][c] {
                    cells[r][c] = .on(color: color.opacity(progress))
                }
            }
        }
        return cells
    }

    /// Phase 4: ">" 常時 + カーソル sin フェード
    private static func completePhasePrompt(time: TimeInterval, color: Color) -> [[DotCell]] {
        var cells = prompt.toCells(onColor: color)
        let phase = (time - transPhaseEnd).truncatingRemainder(dividingBy: cursorPeriod)
        let brightness: Double = phase < cursorPeriod * 0.5
            ? sin(phase / (cursorPeriod * 0.5) * .pi)
            : 0.0
        guard brightness > 0.01 else { return cells }
        let cursorColor = color.opacity(brightness)
        for r in cursorTop...cursorBottom {
            cells[r][cursorCol1] = .on(color: cursorColor)
            cells[r][cursorCol2] = .on(color: cursorColor)
        }
        return cells
    }

    // MARK: - Swarm animation (subagent 並行数)

    /// 13×13 を 3×3 グリッド（各セルに 2×2 ブロックを配置）で分割した際の格子座標→実座標変換。
    /// grid row/col は 0/1/2 を取り、実座標は `2, 6, 10`（ブロック 2 セル + 隙間 2 セル）に対応する。
    private static func gridPos(_ row: Int, _ col: Int) -> (row: Int, col: Int) {
        (row * 4 + 2, col * 4 + 2)
    }

    /// active 数ごとのブロック配置（3×3 grid 座標、読み順 = 点灯順）。
    ///
    /// 1〜3 個は中央行に収め、4 個以上は可能な限り中心 (1,1) に対して対称になるよう選ぶ
    /// （6〜8 個は中央行 (1,*) を優先的に埋めず上下 2 行を使うことで、重心が中心からずれないようにする）。
    /// これにより #20 で問題だった「少数のときブロックが上段に寄る」を解消する。
    private static let swarmGridLayouts: [Int: [(Int, Int)]] = [
        1: [(1, 1)],
        2: [(1, 0), (1, 2)],
        3: [(1, 0), (1, 1), (1, 2)],
        4: [(0, 0), (0, 2), (2, 0), (2, 2)],
        5: [(0, 1), (1, 0), (1, 1), (1, 2), (2, 1)],
        6: [(0, 0), (0, 1), (0, 2), (2, 0), (2, 1), (2, 2)],
        7: [(0, 0), (0, 1), (0, 2), (1, 1), (2, 0), (2, 1), (2, 2)],
        8: [(0, 0), (0, 1), (0, 2), (1, 0), (1, 2), (2, 0), (2, 1), (2, 2)],
        9: [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2)],
    ]

    private static let swarmPulsePeriod = 1.2
    private static let swarmPhaseOffset = 0.25

    /// `active`（1–9 に clamp）個のブロックを `swarmGridLayouts` の配置で点灯。
    /// 各ブロックは index × 0.25s の位相オフセットで脈動する。
    private static func swarmAnimation(time: TimeInterval, active: Int, color: Color) -> [[DotCell]] {
        var cells = emptyCellGrid()
        let clamped = max(1, min(9, active))
        let layout = swarmGridLayouts[clamped] ?? swarmGridLayouts[1]!
        for index in 0..<layout.count {
            let (gridRow, gridCol) = layout[index]
            let (row, col) = gridPos(gridRow, gridCol)
            let phase = (time - Double(index) * swarmPhaseOffset)
                .truncatingRemainder(dividingBy: swarmPulsePeriod)
            let normalizedPhase = phase < 0 ? phase + swarmPulsePeriod : phase
            let brightness = 0.35 + 0.65 * (0.5 + 0.5 * sin(normalizedPhase / swarmPulsePeriod * 2 * .pi))
            let blockColor = color.opacity(brightness)
            cells[row][col] = .on(color: blockColor)
            cells[row][col + 1] = .on(color: blockColor)
            cells[row + 1][col] = .on(color: blockColor)
            cells[row + 1][col + 1] = .on(color: blockColor)
        }
        return cells
    }

    // MARK: - Helpers

    private static func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: cols), count: rows)
    }

    static func emptyCellGrid() -> [[DotCell]] {
        Array(repeating: Array(repeating: DotCell.off, count: cols), count: rows)
    }

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
