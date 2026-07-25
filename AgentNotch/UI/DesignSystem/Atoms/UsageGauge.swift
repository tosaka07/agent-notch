import AgentNotchCore
import Defaults
import SwiftUI

/// 使用率を表す小さな常時表示ゲージ。
///
/// グリフ辞書（`Glyph`）の A'（RING）と E（NUMERIC 5×7）をそのまま使う。
/// 一覧トップバー左翼に、エージェントごとに 1 つずつ横並びで置く想定。
///
/// # 表示形式（`Defaults[.usageGaugeStyle]`、設定から選択）
/// - `.ring`: 13×13 の円環を角度順に点灯。未点灯は `agentType` の色を薄く敷いて
///   「どのエージェントのゲージか」を色相で示す
/// - `.number`: 5×7 の数字を 13×13 枠に収めて 2 桁で出す（数値グリフは 5×7 に一本化）
///
/// **どちらか一方だけを出す**。リングの隣に % テキストを併記すると同じ情報が二重になり、
/// 「設定でリングを選んだのに数字も出る」状態になるため。エージェントの区別は色相で行う。
/// 設定を無視してリングを出したい場所（使用量ページの見出し）は `forcedStyle` を渡す。
///
/// `usedPercent` が nil のとき（初回ポーリング前）は**弧が回るスピナー**を出す。
/// 何も出さないと「ゲージが無い」ように見え、0% の環を出すと「使用量 0」と読み違えるため、
/// 数として読めない動きに置き換える。Reduce Motion では同じ弧を静止させる。
///
/// クリックは呼び出し側の責務（使用量詳細ページへの遷移）。この View 自体は
/// タップ処理を持たない純粋な表示コンポーネントなので Button の label としても使える。
struct UsageGauge: View {
    /// 0〜100 の使用率。未取得（ローディング中）は nil。
    let usedPercent: Double?
    /// どのエージェントの使用率か。点灯／未点灯ドットの色相で識別に使う。nil なら中立色。
    var agentType: AgentType?
    /// グリッド全体の一辺のサイズ。
    var size: CGFloat = 21
    /// 設定を無視して表示形式を固定する。使用量ページの見出しのように、
    /// **隣に数値が別途出ていて形（リング）の方が要る**場所で使う。nil なら設定に従う。
    var forcedStyle: UsageGaugeStyle?
    /// 取得を試みたが値が無い（従量課金で rate limit が無い、資格情報が無い、取得失敗など）。
    ///
    /// `usedPercent == nil` は「まだ取得していない」＝ローディングを意味するので、
    /// **取得できないケースはこのフラグで区別する**。立てるとスピナーを止めて
    /// 輪郭だけの環にする（回り続けると、いつか値が出ると誤解させてしまう）。
    var isUnavailable: Bool = false

    @Default(.usageGaugeStyle) private var settingStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: UsageGaugeStyle { forcedStyle ?? settingStyle }

    private var clampedPercent: Double { min(max(usedPercent ?? 0, 0), 100) }

    /// 点灯ドット（使用済み部分・数字）の色。
    ///
    /// 通常域はエージェントの色相にする。ゲージを Claude / Codex で横並びにしたとき、
    /// **どちらのゲージかを色だけで判別できる**必要があるため（数字表示ではリングの
    /// 薄い track が無く、色相以外の手がかりが無い）。危険域では警告色を優先する。
    private var valueColor: Color {
        switch clampedPercent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: agentType?.color ?? .secondary
        }
    }

    /// 未点灯ドット（リングの残り）の色。エージェントの色相を薄く敷いて識別に使う。
    private var trackColor: Color {
        (agentType?.color ?? .secondary).opacity(0.3)
    }

    private var dot: CGFloat {
        let pitch = size / CGFloat(Glyph.stateSize)
        return max(1, pitch * 2 / 3)
    }

    private var gap: CGFloat {
        max(0, size / CGFloat(Glyph.stateSize) - dot)
    }

    /// スピナーが 1 周する時間。
    private let spinDuration: TimeInterval = 1.1
    /// ローディング終了時に値が満ちるまでの時間。
    private let settleDuration: TimeInterval = 0.55

    /// 値が確定した瞬間の時刻。演出中だけ非 nil。
    @State private var settleStart: Date?

    /// ローディング中か。取得を試みて値が無かった場合（`isUnavailable`）は含まない。
    private var isLoading: Bool { usedPercent == nil && !isUnavailable }

    var body: some View {
        Group {
            if isLoading, !reduceMotion {
                // ドット単位で位置が飛ぶ離散アニメーションなので、暗黙アニメーションではなく
                // TimelineView で位相を送る（`StateGlyphView` と同じ方式）。
                TimelineView(.animation(minimumInterval: spinDuration / 40)) { context in
                    GlyphView(bitmap: spinnerBitmap(at: context.date), dot: dot, gap: gap)
                }
            } else if let settleStart, !reduceMotion {
                TimelineView(.animation(minimumInterval: settleDuration / 40)) { context in
                    GlyphView(
                        bitmap: settleBitmap(at: context.date, from: settleStart),
                        dot: dot,
                        gap: gap
                    )
                }
            } else {
                GlyphView(bitmap: bitmap, dot: dot, gap: gap)
            }
        }
        .onChange(of: isLoading) { wasLoading, nowLoading in
            // ローディングが終わった瞬間だけ演出する。以降の値更新（3 分ごとの再取得）で
            // 毎回 0 から満ち直すと、視界の端で何度も動いて気が散るため。
            // 値を得られずに終わった場合（isUnavailable）は満ちるものが無いので出さない。
            guard wasLoading, !nowLoading, usedPercent != nil else { return }
            settleStart = Date()
        }
        .task(id: settleStart) {
            guard settleStart != nil else { return }
            // 演出が終わったら TimelineView を畳んでフレーム毎の再評価を止める。
            try? await Task.sleep(for: .seconds(settleDuration))
            settleStart = nil
        }
        .accessibilityElement()
        .accessibilityLabel(agentType.map { "\($0.displayName) の使用率" } ?? "使用率")
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        if let usedPercent { return "\(Int(min(max(usedPercent, 0), 100).rounded()))パーセント" }
        return isUnavailable ? "取得なし" : "取得中"
    }

    /// ローディング → 値確定の演出。
    ///
    /// 回る弧を、そのまま 12 時から目標値まで**満ちる環**に引き継ぐ（リング表示）／
    /// 0 から目標値まで**駆け上がる数字**にする（数字表示）。どちらも終端でわずかに
    /// 行き過ぎてから戻り、「値が決まって止まった」ことが動きで分かるようにする。
    private func settleBitmap(at date: Date, from start: Date) -> GlyphBitmap {
        let elapsed = date.timeIntervalSince(start)
        let progress = min(1, max(0, elapsed / settleDuration))
        let shown = clampedPercent * easeOutBack(progress)
        switch style {
        case .ring:
            return Glyph.ring(
                percent: min(100, max(0, shown)),
                lit: valueColor,
                track: trackColor
            )
        case .number:
            let value = min(99, max(0, Int(shown.rounded())))
            return Glyph.framedNumber(String(value), color: valueColor)
        }
    }

    /// 0→1。終端をわずかに超えてから戻る（カチッと止まる感じを出す）。
    private func easeOutBack(_ t: Double) -> Double {
        let overshoot = 1.2
        let p = t - 1
        return 1 + (overshoot + 1) * (p * p * p) + overshoot * (p * p)
    }

    private func spinnerBitmap(at date: Date) -> GlyphBitmap {
        let elapsed = date.timeIntervalSinceReferenceDate
        let phase = elapsed.truncatingRemainder(dividingBy: spinDuration) / spinDuration
        return Glyph.ringSpinner(
            phase: phase,
            lit: agentType?.color ?? .secondary,
            track: trackColor.opacity(0.4)
        )
    }

    private var bitmap: GlyphBitmap {
        guard usedPercent != nil else {
            if isUnavailable {
                // 取得できなかった場合は輪郭だけの環。動かさず、点灯部も作らないので
                // 「0%」とも「取得中」とも読めない = 値が無いことがそのまま見える。
                return Glyph.ring(percent: 0, lit: trackColor, track: trackColor)
            }
            // Reduce Motion 時のローディング表示。0% の環と混ざらないよう、
            // 弧を一定の位相で止めて出す。
            return Glyph.ringSpinner(
                phase: 0,
                lit: agentType?.color ?? .secondary,
                track: trackColor.opacity(0.4)
            )
        }
        switch style {
        case .ring:
            return Glyph.ring(percent: clampedPercent, lit: valueColor, track: trackColor)
        case .number:
            // 2 桁までしか描けないため 100% は 99 に丸める。
            return Glyph.framedNumber(String(min(99, Int(clampedPercent.rounded()))), color: valueColor)
        }
    }
}

#Preview("Usage Gauge") {
    VStack(spacing: 20) {
        ForEach([12.0, 78.0, 95.0], id: \.self) { percent in
            HStack(spacing: 20) {
                UsageGauge(usedPercent: percent, agentType: .claudeCode, size: 32)
                UsageGauge(usedPercent: percent, agentType: .codex, size: 32)
                Text("\(Int(percent))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        UsageGauge(usedPercent: nil, agentType: .claudeCode, size: 32)
    }
    .padding(24)
    .background(Color.black)
}
