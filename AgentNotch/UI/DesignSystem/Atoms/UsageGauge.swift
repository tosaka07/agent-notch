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
/// `usedPercent` が nil のとき（初回ポーリング前）は輪郭だけのプレースホルダを出す。
/// 何も出さないと「ゲージが無い」ように見えて違和感があるため。
///
/// クリックは呼び出し側の責務（使用量詳細ページへの遷移）。この View 自体は
/// タップ処理を持たない純粋な表示コンポーネントなので Button の label としても使える。
struct UsageGauge: View {
    /// 0〜100 の使用率。未取得（ローディング中）は nil。
    let usedPercent: Double?
    /// どのエージェントの使用率か。未点灯ドットの色相で識別に使う。nil なら中立色。
    var agentType: AgentType?
    /// グリッド全体の一辺のサイズ。
    var size: CGFloat = 21

    @Default(.usageGaugeStyle) private var style

    private var clampedPercent: Double { min(max(usedPercent ?? 0, 0), 100) }

    /// 点灯ドット（使用済み部分・数字）の色。
    private var valueColor: Color {
        switch clampedPercent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: .secondary
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

    var body: some View {
        GlyphView(bitmap: bitmap, dot: dot, gap: gap)
            .accessibilityElement()
            .accessibilityLabel(agentType.map { "\($0.displayName) の使用率" } ?? "使用率")
            .accessibilityValue(
                usedPercent == nil ? "取得中" : "\(Int(clampedPercent.rounded()))パーセント"
            )
    }

    private var bitmap: GlyphBitmap {
        guard usedPercent != nil else {
            return Glyph.ring(percent: 0, lit: trackColor, track: trackColor)
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
