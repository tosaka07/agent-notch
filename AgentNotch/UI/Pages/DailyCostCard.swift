import AgentNotchCore
import Defaults
import SwiftUI

/// One daily-cost card, covering a single agent.
///
/// # Why it animates in
/// While the aggregation runs, a wave travels across the grid
/// (`UsageBlockChart.loadingPhase`). Swapping straight to the finished figure
/// the moment it completes makes something that was moving stop dead. Instead
/// **the values rise from left to right once the wave recedes**, carrying the
/// motion from loading into the result.
///
/// The card is a separate `View` because that animation needs its own rise
/// state (`@State`), which a function returning `some View` cannot hold.
struct DailyCostCard: View {
    let agentType: AgentType
    let report: DailyCostReport
    /// Number of days the chart shows.
    let dayCount: Int

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When the rise started. Reset to nil once it is done, collapsing the
    /// `TimelineView`.
    @State private var revealStart: Date?
    @State private var isRevealed = false

    /// How long the rise takes.
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
            // The card heading says only whose and how much. Cost, period, and
            // "estimated" are already stated by the section heading, so they
            // are not repeated.
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
                .accessibilityLabel(L("Daily cost for \(agentType.displayName)"))
                .accessibilityValue(L("\(CostCalculator.formatCost(total)) over the last \(dayCount) days"))

            if !report.unsupportedModels.isEmpty {
                Text(l10n: "Excluded, no pricing: \(report.unsupportedModels.joined(separator: ", "))")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        // Cards side by side share a height — if only one carries a note, the
        // mismatched backgrounds look sloppy. Expanding before the background is
        // applied stretches the card itself to the HStack's height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelCard()
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
            // Once the animation is over, collapse the TimelineView to stop
            // re-evaluating every frame.
            try? await Task.sleep(for: .seconds(revealDuration))
            isRevealed = true
            revealStart = nil
        }
    }

    /// The chart carries its own scale: the vertical axis is the peak amount at
    /// the ceiling and 0, the horizontal axis the dates directly under the
    /// leftmost and rightmost columns. Placed outside, they would not line up
    /// with the figure.
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

    /// Amount printed at the vertical axis's ceiling. With every day at 0 there
    /// is no ceiling, so no axis is drawn.
    private func peakLabel(_ values: [Double]) -> String? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return CostCalculator.formatCost(peak)
    }

    private func dayLabel(_ day: Date?) -> String {
        guard let day else { return "" }
        return Self.dayFormatter.string(from: day)
    }
}
