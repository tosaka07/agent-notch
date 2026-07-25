import SwiftUI

/// 状態グリフ（13×13）をアニメーション付きで描く View。
///
/// # アニメーション仕様（モックの 4a フィルムストリップ準拠）
/// | 状態 | 周期 | 動き |
/// | --- | --- | --- |
/// | STANDBY | 2400ms | 環の半径のみ ±1 マス呼吸（点の増減なし） |
/// | THINKING | 1600ms | 正弦波の位相を 1 周送る（行は整数マスに丸め） |
/// | WORKING | 900ms | 核が半径 2→4 で脈動 |
/// | SWARM(n) | 120ms/枠 | 起動順に枠が埋まる（静的。数の変化で動く） |
/// | ALERT | 1000ms | 55/45 デューティで点滅。消灯側も 0.22 で残す |
/// | COMPLETE | 480ms | 左下からチェックを描き足し、以後保持 |
///
/// # 再評価頻度
/// フレーム毎に評価する必要があるのは半径・位相が連続的に変わる standby / thinking /
/// working / complete のみ。点滅系（alert / planReview / fault）と静的な swarm は
/// 粗い tick で足りるため `TimelineView(.animation(minimumInterval:))` を使い分ける。
struct StateGlyphView: View {
    let state: Glyph.State
    /// グリッド全体の一辺。13 マス（ドット 2 + 間隔 1 → ピッチ 3）を基準に逆算する。
    var size: CGFloat = 26
    /// complete の描き始め時刻。nil なら絶対時刻を使う。
    var animationStartTime: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 13 マスを `size` に収めるためのドット径（ピッチの 2/3 が点、1/3 が隙間）。
    private var dot: CGFloat {
        let pitch = size / CGFloat(Glyph.stateSize)
        return max(1, pitch * 2 / 3)
    }

    private var gap: CGFloat {
        let pitch = size / CGFloat(Glyph.stateSize)
        return max(0, pitch - dot)
    }

    /// 連続的に形が変わるパターンだけフレーム毎に評価する。
    private var minimumTickInterval: TimeInterval? {
        switch state {
        case .standby, .thinking, .working, .complete: nil
        // 点滅・静的パターンは 0.1s 刻みで十分（デューティの切り替わりが読めればよい）。
        case .alert, .planReview, .fault, .swarm: 0.1
        }
    }

    var body: some View {
        if reduceMotion {
            // Reduce Motion では動かさず、いちばん情報量の多い位相で静止させる。
            GlyphView(bitmap: Glyph.state(state, phase: state == .complete ? 1 : 0.5), dot: dot, gap: gap)
        } else if let interval = minimumTickInterval {
            TimelineView(.animation(minimumInterval: interval)) { context in
                GlyphView(bitmap: bitmap(at: context.date), dot: dot, gap: gap)
            }
        } else {
            TimelineView(.animation) { context in
                GlyphView(bitmap: bitmap(at: context.date), dot: dot, gap: gap)
            }
        }
    }

    private func bitmap(at date: Date) -> GlyphBitmap {
        Glyph.state(state, phase: phase(at: date))
    }

    /// 0〜1 の位相。loop しないパターン（complete）は 1 で止める。
    private func phase(at date: Date) -> Double {
        let elapsed: TimeInterval
        if let animationStartTime {
            elapsed = max(0, date.timeIntervalSince(animationStartTime))
        } else {
            elapsed = date.timeIntervalSinceReferenceDate
        }
        let duration = state.duration
        guard duration > 0 else { return 0 }
        guard state.loops else { return min(1, elapsed / duration) }
        return (elapsed.truncatingRemainder(dividingBy: duration)) / duration
    }
}

#Preview("A · STATE") {
    let states: [(String, Glyph.State)] = [
        ("STANDBY", .standby), ("THINKING", .thinking), ("WORKING", .working),
        ("SWARM(5)", .swarm(active: 5)), ("ALERT", .alert), ("PLAN REVIEW", .planReview),
        ("COMPLETE", .complete), ("FAULT", .fault),
    ]
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), spacing: 18) {
        ForEach(states, id: \.0) { item in
            HStack(spacing: 12) {
                StateGlyphView(state: item.1, size: 26)
                Text(item.0)
                    .font(DSTypography.mono(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DSColors.inkDim)
            }
        }
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
