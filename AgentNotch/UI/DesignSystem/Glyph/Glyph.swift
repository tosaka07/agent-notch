import SwiftUI

/// Agent Notch のグリフ辞書。
///
/// **フォント文字（`□▪■` / `◆◇` / `●`）は使わない。** すべて格子上のドットで描く。
/// 「形が状態を語る。色は補助であり、色が消えても読める」が原則。
///
/// | 分類 | サイズ | 用途 |
/// | --- | --- | --- |
/// | A · STATE | 13×13 | セッション状態（compact 左翼 / カード左列） |
/// | B · TASK | 5×5 | タスクの未着手 / 進行中 / 完了 |
/// | C · SUBAGENT / MEMBER | 5×5 | subagent の実行中 / 空き枠、teammate |
/// | D · USAGE | 3×3 | 使用量の目盛り 1 ブロック（10 個 = 100%） |
/// | E · NUMERIC | 5×7 | 数値と `n/m` カウンタ（3×5 / 4×5 は使わない） |
enum Glyph {
    // MARK: - A · STATE 13×13

    static let stateSize = 13

    /// 状態グリフの図柄。アニメーションは `phase`（0〜1 の位相）で表現する。
    ///
    /// 動きの仕様（周期 / イージング）は `StateGlyph.duration` を参照。
    enum State: Equatable {
        /// idle / starting — 静止した環
        case standby
        /// thinking / compacting — 波形
        case thinking
        /// tool 実行 — 塗りの核
        case working
        /// subagent 並行 n 件 — 9 枠を埋める
        case swarm(active: Int)
        /// 承認待ち / 質問 — 感嘆符
        case alert
        /// plan の承認待ち — 三本線
        case planReview
        /// 完了 — チェック
        case complete
        /// エラー — ×
        case fault

        /// アニメーション 1 周の長さ（秒）。`loop == false` は 1 回だけ再生する。
        var duration: TimeInterval {
            switch self {
            case .standby: 2.4
            case .thinking: 1.6
            case .working: 0.9
            case .swarm: 0.12  // 1 枠あたり
            case .alert: 1.0
            case .planReview: 1.0
            case .complete: 0.48
            case .fault: 0.32
            }
        }

        /// 繰り返し再生するか。complete は描き終えたら止まる。
        var loops: Bool {
            switch self {
            case .complete, .swarm: false
            default: true
            }
        }
    }

    /// 状態グリフを位相 `phase`（0〜1）で評価する。
    static func state(_ state: State, phase: Double = 0) -> GlyphBitmap {
        switch state {
        case .standby: standby(phase: phase)
        case .thinking: thinking(phase: phase)
        case .working: working(phase: phase)
        case .swarm(let active): swarm(active: active)
        case .alert: alert(phase: phase)
        case .planReview: planReview(phase: phase)
        case .complete: complete(progress: min(1, phase * 1.15))
        case .fault: fault(phase: phase)
        }
    }

    /// 環が 1 マス分だけ呼吸する。**点の増減はせず半径のみ**動かす。
    private static func standby(phase: Double) -> GlyphBitmap {
        let radius = 3.5 + 0.9 * sin(phase * 2 * .pi)
        return GlyphBitmap.square(stateSize, on: DSColors.signalIdle) { x, y in
            let d = distance(x, y)
            return d > radius - 0.75 && d < radius + 0.75
        }
    }

    /// 正弦波の位相を 1 周ずらす。行は必ず整数マスへ丸める。
    private static func thinking(phase: Double) -> GlyphBitmap {
        GlyphBitmap.square(stateSize, on: DSColors.signalThinking) { x, y in
            let wave = 6 + 3 * sin((Double(x) / 12) * 2 * .pi - phase * 2 * .pi)
            return y == Int(wave.rounded())
        }
    }

    /// 核が半径 2→4 マスで脈打つ。tool 呼び出しごとに 1 拍。
    private static func working(phase: Double) -> GlyphBitmap {
        let radius = 2.2 + 1.6 * (0.5 - 0.5 * cos(phase * 2 * .pi))
        return GlyphBitmap.square(stateSize, on: DSColors.signalWorking) { x, y in
            distance(x, y) <= radius
        }
    }

    /// 13×13 に 3×3 の枠を 9 個。点灯数 = 並行数（起動順に埋まる）。
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

    /// 感嘆符。点滅は 55/45 のデューティで、**消灯側も 0.22 で残す**（形が消えない）。
    private static func alert(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.55
        let color = lit ? DSColors.signalAlert : DSColors.signalAlert.opacity(0.22)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (x >= 5 && x <= 7 && y >= 2 && y <= 7) || (x >= 5 && x <= 7 && y >= 9 && y <= 10)
        }
    }

    /// 三本線（plan の文面）。alert と同じデューティで点滅させるが色で区別する。
    private static func planReview(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.6
        let color = lit ? DSColors.signalPlan : DSColors.signalPlan.opacity(0.22)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (y == 3 && x >= 2 && x <= 10) || (y == 6 && x >= 2 && x <= 7) || (y == 9 && x >= 2 && x <= 10)
        }
    }

    /// チェックを左下から描き足す。完了後 1.2s で standby へ戻す（呼び出し側の責務）。
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

    /// ×。細かくフリッカさせて「壊れている」感を出す。
    private static func fault(phase: Double) -> GlyphBitmap {
        let lit = phase < 0.7
        let color = lit ? DSColors.signalError : DSColors.signalError.opacity(0.25)
        return GlyphBitmap.square(stateSize, on: color) { x, y in
            (abs(x - y) <= 1 || abs(x + y - 12) <= 1) && x >= 2 && x <= 10 && y >= 2 && y <= 10
        }
    }

    private static func distance(_ x: Int, _ y: Int) -> Double {
        let dx = Double(x - 6), dy = Double(y - 6)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - A' · RING 13×13（使用量の円環ゲージ）

    /// 円環を構成するセルの index を 12 時から時計回りに並べたもの。
    ///
    /// `ring` と `ringSpinner` で同じ環を共有する（片方だけ形が変わると
    /// ローディング → 値確定の切り替わりで環が飛んで見える）。格子サイズは固定なので
    /// 一度だけ計算する。
    static let ringCellIndices: [Int] = {
        let center = 6.0, radius = 5.2
        var ordered: [(index: Int, angle: Double)] = []
        for y in 0..<stateSize {
            for x in 0..<stateSize {
                let dx = Double(x) - center, dy = Double(y) - center
                let d = (dx * dx + dy * dy).squareRoot()
                guard d > radius - 0.75, d < radius + 0.75 else { continue }
                var angle = atan2(Double(x) - center, center - Double(y)) * 180 / .pi
                if angle < 0 { angle += 360 }
                ordered.append((y * stateSize + x, angle))
            }
        }
        return ordered.sorted { $0.angle < $1.angle }.map(\.index)
    }()

    /// 13×13 の格子上の円環。角度順に `percent` まで点灯する。
    /// 未点灯セルは `track`（エージェント色を薄く敷いて識別に使う）。
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

    /// ローディング中の円環。値の代わりに**弧が 1 周し続ける**ことで「まだ取得中」を示す。
    ///
    /// 値が確定していない間に 0% の環を出すと「使用量 0」と読み違えられるため、
    /// 数として読めない動き（回る弧）に置き換える。弧は先頭が最も濃く尾に向かって薄れ、
    /// 進行方向が形だけで分かるようにする（色が消えても読める、という原則を守る）。
    ///
    /// - Parameters:
    ///   - phase: 0〜1 の位相。1 で 1 周。範囲外は環状に丸める。
    ///   - arcRatio: 弧の長さ（環全体に対する比）。
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
            // 尾は head の手前側（= 進行方向の後ろ）に伸びる。
            let position = ((head - k) % count + count) % count
            let fade = 1 - Double(k) / Double(arcCount)
            colorByIndex[indices[position]] = lit.opacity(0.25 + 0.75 * fade)
        }
        return ringBitmap(colorByIndex: colorByIndex)
    }

    /// 環のセル色マップから 13×13 のビットマップを組む。環に属さないセルは消灯。
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

    /// タスクの状態。未着手 = 輪郭のみ / 進行中 = 輪郭 + 芯 / 完了 = 塗り。
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

    /// subagent 実行中 — 菱形の塗り。
    static func subagentRunning(color: Color = DSColors.signalWorking) -> GlyphBitmap {
        GlyphBitmap.square(5, on: color) { x, y in abs(x - 2) + abs(y - 2) <= 2 }
    }

    /// subagent の空き枠 — 菱形の輪郭。
    static func subagentIdle(color: Color = DSColors.inkMute) -> GlyphBitmap {
        GlyphBitmap.square(5, on: color) { x, y in abs(x - 2) + abs(y - 2) == 2 }
    }

    /// teammate — 中央 3×3 の塊。
    ///
    /// モック（2a）は「円」と書いているが、5×5 の格子では半径 2.1 の円と
    /// 菱形（`subagentRunning`）が**まったく同じ形になる**（角が落ちて十字＋対角が埋まる）。
    /// 「形が状態を語る」原則に反するため、teammate は中央 3×3 の塊にして
    /// 菱形（subagent）・菱形輪郭（空き枠）・全塗り（task done）と区別できるようにした。
    static func member(color: Color = DSColors.inkDim) -> GlyphBitmap {
        GlyphBitmap.square(5, on: color) { x, y in
            x >= 1 && x <= 3 && y >= 1 && y <= 3
        }
    }

    // MARK: - D · USAGE 3×3 ブロック

    /// 使用量の目盛り 1 ブロック。10 個で 100%。
    ///
    /// 消費済み = 塗り、残量 = 輪郭。**severity は色だけを変え、目盛り（ブロック数）は
    /// 変えない** ので、API 由来の severity と自前しきい値が同じ目盛りに乗る。
    ///
    /// 輪郭ブロックの中心は「消灯」として返す。薄く見せたい場合は
    /// `GlyphView(ghost:)` に色を渡す（点灯/消灯の意味づけを bitmap 側に持たせないため）。
    static func usageBlock(filled: Bool, color: Color) -> GlyphBitmap {
        GlyphBitmap.square(3, on: filled ? color : color.opacity(0.5)) { x, y in
            filled || x == 0 || y == 0 || x == 2 || y == 2
        }
    }

    // MARK: - E · NUMERIC 5×7

    /// 5×7 のビットマップフォント。数値・`n/m`・`%`・`$` をこの 1 種で書く。
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
    /// 1 文字あたりの幅（5 マス + 字間 1 マス）。
    private static let numericStride = 6

    /// 文字列を 5×7 のドットで描く。文字ごとに色を変えられる（`n/m` の分母を薄くする等）。
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
                // 字間（6 マス目）は常に空ける。
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

    /// 状態グリフと同じ 13×13 枠に 5×7 の数字を収める（枠付き数値）。
    static func framedNumber(_ text: String, color: Color = DSColors.ink) -> GlyphBitmap {
        let inner = number(text, color: color)
        let offsetX = Int(((Double(stateSize) - Double(inner.cols)) / 2).rounded())
        let offsetY = Int(((Double(stateSize) - Double(numericRows)) / 2).rounded())

        var cells = GlyphBitmap.empty(rows: stateSize, cols: stateSize).cells
        for y in 0..<inner.rows {
            for x in 0..<inner.cols {
                let ty = y + offsetY, tx = x + offsetX
                guard ty >= 0, ty < stateSize, tx >= 0, tx < stateSize else { continue }
                cells[ty][tx] = inner.cell(row: y, col: x)
            }
        }
        return GlyphBitmap(rows: stateSize, cols: stateSize, cells: cells)
    }
}
