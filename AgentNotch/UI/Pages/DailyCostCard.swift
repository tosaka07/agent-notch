import AgentNotchCore
import Defaults
import SwiftUI

/// 日毎コストのカード 1 枚（エージェント 1 つ分）。
///
/// # 出るときにアニメーションする理由
/// 集計中は格子に波を流している（`UsageBlockChart.loadingPhase`）。集計が終わった瞬間に
/// 完成した図へ差し替わると、動いていたものが突然止まって見える。**波が引いたあとに
/// 値が左から順に立ち上がる**ようにして、ローディングから結果へ動きを繋ぐ。
///
/// カードを `View` として切り出しているのは、この演出のために立ち上がりの状態
/// （`@State`）を持つ必要があるため（`some View` を返す関数では持てない）。
struct DailyCostCard: View {
    let agentType: AgentType
    let report: DailyCostReport
    /// チャートに出す日数。
    let dayCount: Int

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 立ち上がりの開始時刻。演出が済んだら nil に戻して `TimelineView` を畳む。
    @State private var revealStart: Date?
    @State private var isRevealed = false

    /// 立ち上がりにかける時間。
    private let revealDuration: TimeInterval = 0.7

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }
    private var scale: CGFloat { textSize.scale }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private var days: [DailyCost] { report.recentDaysFilled(count: dayCount) }
    private var values: [Double] { days.map(\.estimatedCostUSD) }

    var body: some View {
        let values = self.values
        let total = values.reduce(0, +)

        VStack(alignment: .leading, spacing: 9) {
            // カードの見出しは「誰の」と「いくら」だけ。COST / 期間 / 推定は
            // セクション見出しが言っているので繰り返さない。
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                AgentMark(agentType: agentType, size: s(9), alignedWithFontSize: s(9))
                Text(agentType.displayName.uppercased())
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(DSColors.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(CostCalculator.formatCost(total))
                    .font(DSTypography.Native.callout(scale, weight: .semibold))
                    .foregroundStyle(DSColors.ink)
                    .lineLimit(1)
            }

            chart(values: values)
                .accessibilityElement()
                .accessibilityLabel("\(agentType.displayName) の日毎コスト")
                .accessibilityValue("直近\(dayCount)日で \(CostCalculator.formatCost(total))")

            if !report.unsupportedModels.isEmpty {
                Text("単価未対応で除外: \(report.unsupportedModels.joined(separator: ", "))")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        // 横並びのカードは高さを揃える（片方だけ注記があると背景の高さがずれて雑に見える）。
        // 背景を敷く前に広げるので、カード自体が HStack の高さまで伸びる。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DSColors.lineDefault, lineWidth: 0.5)
        )
        .onAppear {
            guard !isRevealed else { return }
            if reduceMotion {
                isRevealed = true
            } else {
                revealStart = Date()
            }
        }
        .task(id: revealStart) {
            guard revealStart != nil else { return }
            // 演出が終わったら TimelineView を畳んでフレーム毎の再評価を止める。
            try? await Task.sleep(for: .seconds(revealDuration))
            isRevealed = true
            revealStart = nil
        }
    }

    /// 目盛りはチャート自身に持たせる（縦軸 = 天井のピーク金額と 0、
    /// 横軸 = 左端・右端の列の真下の日付）。外に並べると図と対応が取れない。
    @ViewBuilder
    private func chart(values: [Double]) -> some View {
        if let revealStart, !isRevealed {
            TimelineView(.animation(minimumInterval: revealDuration / 30)) { context in
                grid(
                    values: values,
                    progress: min(1, max(0, context.date.timeIntervalSince(revealStart) / revealDuration))
                )
            }
        } else {
            grid(values: values, progress: 1)
        }
    }

    private func grid(values: [Double], progress: Double) -> UsageBlockChart {
        UsageBlockChart(
            values: values,
            startLabel: dayLabel(days.first?.day),
            endLabel: dayLabel(days.last?.day),
            peakLabel: peakLabel(values),
            revealProgress: progress,
            labelFont: DSTypography.mono(s(11)),
            labelFontSize: s(11),
            axisWidth: s(44)
        )
    }

    /// 縦軸の天井に出す金額。全日 0 のときは軸を出さない（天井が無いので）。
    private func peakLabel(_ values: [Double]) -> String? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return CostCalculator.formatCost(peak)
    }

    private func dayLabel(_ day: Date?) -> String {
        guard let day else { return "" }
        return Self.dayFormatter.string(from: day)
    }
}
