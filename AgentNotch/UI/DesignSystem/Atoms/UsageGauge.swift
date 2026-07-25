import Defaults
import SwiftUI

/// 使用率を表す小さな常時表示ゲージ（リング or 数字）。タップで表示形式を切り替えられる。
///
/// `SessionDetailView` 右下に常設する想定。ここでは「今どれくらい使っているか」だけを
/// 一目で見せ、週次・モデル別などの内訳は展開時の詳細（`UsageDetailSection`）に任せる。
/// 使用率 70% / 90% で `DSColors.signalAlert` / `signalError` にエスカレーションし、
/// それ未満は `.secondary`（面ではなく縁取り・文字のみに signal 色を使うルールに従う）。
struct UsageGauge: View {
    /// 0〜100 の使用率。
    let usedPercent: Double
    var size: CGFloat = 22

    @Default(.usageGaugeStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    private var color: Color {
        switch clampedPercent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: .secondary
        }
    }

    var body: some View {
        Button {
            style = style.toggled
        } label: {
            Group {
                switch style {
                case .ring: ring
                case .number: number
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("使用率")
        .accessibilityValue("\(Int(clampedPercent.rounded()))パーセント")
        .accessibilityHint("タップで表示形式を切り替え")
        .help("使用率 \(Int(clampedPercent.rounded()))%（タップで表示切替）")
    }

    private var ring: some View {
        let lineWidth = max(2, size * 0.14)
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedPercent / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: clampedPercent)
        }
    }

    private var number: some View {
        Text("\(Int(clampedPercent.rounded()))%")
            .font(.system(size: size * 0.4, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

#Preview("Usage Gauge") {
    HStack(spacing: 16) {
        UsageGauge(usedPercent: 12, size: 28)
        UsageGauge(usedPercent: 78, size: 28)
        UsageGauge(usedPercent: 95, size: 28)
    }
    .padding(16)
}
