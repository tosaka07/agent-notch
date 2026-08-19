import AgentNotchCore
import Defaults
import SwiftUI

/// UI for the `usage` mode: the full usage breakdown page.
///
/// Opened by clicking the `UsageGauge` in the session list's top-bar left wing.
/// Where that gauge shows the single fact of "how much right now", this page
/// shows everything that could be fetched.
///
/// # Structure
/// ```
/// ┌─ CLAUDE ─────────────────────────────────────────────┐
/// │ ◯  CLAUDE · Current session     2h 10m left           │
/// │    48% (5×7 glyph)              Resets today 23:14    │
/// ├──────────────────────────────────────────────────────┤
/// │ SESSION  NOW  ■■■■■□□□□□  48%  2h left    23:14      │
/// │ WEEKLY        ■■■■■■□□□□  62%  2d left    7/28 09:00 │
/// └──────────────────────────────────────────────────────┘
/// ```
/// **Sections are split per provider**, so the structure itself shows that
/// SESSION / WEEKLY / per-model are Claude-specific. The scale is glyph D from
/// the dictionary: ten 3×3 blocks = 100%.
///
/// Before the first poll returns, showing nothing would look broken, so a
/// placeholder appears: an outline-only gauge with an empty scale.
struct UsagePageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var usageCoordinator: UsageCoordinator
    @ObservedObject var dailyCostCoordinator: DailyCostCoordinator
    let keyboardInteraction: KeyboardInteractionController

    @Default(.textSize) private var textSize
    @Default(.codexIntegrationEnabled) private var codexIntegrationEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Number of days shown in the bar chart.
    private let chartDayCount = 14
    /// Horizontal content inset, generous enough not to be eaten by the notch
    /// panel's rounded corners.
    private let contentPadding: CGFloat = 20

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }
    private var scale: CGFloat { textSize.scale }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLocalization.language.locale
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let absoluteResetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLocalization.language.locale
        f.setLocalizedDateFormatFromTemplate("Md HH:mm")
        return f
    }()

    private var snapshot: UsageSnapshot? { usageCoordinator.snapshot }

    /// Display data for one window. Before the fetch it serves as a placeholder
    /// with a nil `window`.
    private struct Row: Identifiable {
        let id: String
        let label: String
        let window: UsageWindow?
    }

    private var claudeRows: [Row] {
        guard let claude = snapshot?.claude else {
            return [
                Row(id: "session", label: L("Session").uppercased(), window: nil),
                Row(id: "week", label: L("Weekly").uppercased(), window: nil),
            ]
        }
        var rows: [Row] = []
        if let session = claude.session {
            rows.append(Row(id: "session", label: L("Session").uppercased(), window: session))
        }
        if let week = claude.weekAllModels {
            rows.append(Row(id: "week", label: L("Weekly").uppercased(), window: week))
        }
        for model in claude.weekModels {
            rows.append(
                Row(
                    id: "week-\(model.modelLabel)",
                    label: L("\(model.modelLabel) weekly").uppercased(),
                    window: model.window
                )
            )
        }
        return rows
    }

    private var codexRows: [Row] {
        // Mirrors `claudeRows`: with nothing fetched the row labels still appear, so the section
        // keeps its shape and the empty slots are visibly empty rather than absent.
        guard let codex = snapshot?.codex else {
            return [
                Row(id: "codex-5h", label: L("5-hour window").uppercased(), window: nil),
                Row(id: "codex-week", label: L("Weekly").uppercased(), window: nil),
            ]
        }
        var rows: [Row] = []
        if let primary = codex.primary {
            rows.append(Row(id: "codex-5h", label: L("5-hour window").uppercased(), window: primary))
        }
        if let secondary = codex.secondary {
            rows.append(Row(id: "codex-week", label: L("Weekly").uppercased(), window: secondary))
        }
        if let individualLimit = codex.individualLimit {
            rows.append(
                Row(
                    id: "codex-allowance",
                    label: L("Usage allowance").uppercased(),
                    window: individualLimit.usageWindow
                )
            )
        }
        return rows
    }

    private var codexHeadlineLabel: String {
        guard let codex = snapshot?.codex else { return L("Usage") }
        if codex.primary != nil { return L("Current 5-hour window") }
        if codex.secondary != nil { return L("Weekly") }
        if codex.individualLimit != nil { return L("Usage allowance") }
        return L("Usage")
    }

    private var codexNote: String? {
        guard let codex = snapshot?.codex else { return unavailableNote(for: .codex) }
        if let allowance = codex.individualLimit {
            let used = codexAmountText(allowance.used)
            let limit = codexAmountText(allowance.limit)
            let remaining = Int(allowance.remainingPercent.rounded())
            return L("Used \(used) / \(limit)") + " · " + L("\(remaining) percent remaining")
        }
        return codexRows.isEmpty ? unavailableNote(for: .codex) : nil
    }

    /// The note that replaces the numbers when a provider has nothing to show.
    ///
    /// The section itself always stays on screen, so this is the only thing telling the user why
    /// it is empty — and, where there is one, what to do about it. Returns nil before the first
    /// poll completes, when the honest answer is "still loading".
    private func unavailableNote(for agentType: AgentType) -> String? {
        guard let snapshot else { return nil }
        // A fetch that produced no window without recording a cause is treated as "this account
        // has no limit to report", which is the only benign way to get here.
        return (snapshot.unavailableReason(for: agentType) ?? .noLimits).explanation
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    providerSection(
                        agentType: .claudeCode,
                        headlineLabel: L("Current session"),
                        rows: claudeRows,
                        trailingLabel: nil,
                        note: snapshot?.claude == nil ? unavailableNote(for: .claudeCode) : nil
                    )

                    // The section stays even when Codex reported nothing, so the page keeps a
                    // stable shape and can explain the gap. It is dropped only when the user
                    // turned the integration off, where there is nothing to explain.
                    if codexIntegrationEnabled {
                        providerSection(
                            agentType: .codex,
                            headlineLabel: codexHeadlineLabel,
                            rows: codexRows,
                            trailingLabel: snapshot?.codex?.planType?.uppercased(),
                            note: codexNote
                        )
                    }

                    costSection

                    footer
                }
                .padding(.horizontal, contentPadding)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        .onReceive(keyboardInteraction.commands) { event in
            guard keyboardInteraction.isEngaged,
                keyboardInteraction.context == .usage,
                event.command == .refresh,
                !isRefreshing
            else { return }
            usageCoordinator.forceRefresh()
            dailyCostCoordinator.forceRefresh()
        }
    }

    // MARK: - Top bar

    /// Reserves the physical notch's height, with navigation and the page title
    /// in the left wing and refresh in the right.
    private var topBar: some View {
        HStack(spacing: 0) {
            NotchBackButton(accessibilityLabel: L("Back to list")) {
                viewModel.backToList()
            }

            Text(verbatim: L("Usage").uppercased())
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))
                .padding(.leading, 4)

            Spacer()

            reloadButton
                .padding(.trailing, contentPadding)
        }
        .frame(height: viewModel.physicalNotchHeight + 4)
    }

    private var isRefreshing: Bool {
        usageCoordinator.isRefreshing || dailyCostCoordinator.isRefreshing
    }

    /// Manually refetches both usage and daily cost without waiting for the
    /// polling interval.
    private var reloadButton: some View {
        Button {
            usageCoordinator.forceRefresh()
            dailyCostCoordinator.forceRefresh()
        } label: {
            // `arrow.clockwise` is asymmetric — the arrowhead pulls its visual
            // center away from the geometric one — so spinning it about the
            // frame's center makes the circle wobble. What spins is a true
            // circular arc drawn here; the arrow icon appears only at rest.
            //
            // An implicit animation with repeatForever would have its rotation
            // reset partway through on a page like this, where @Published
            // updates re-evaluate the body constantly. This is the same reason
            // `UsageGauge`'s spinner avoids it. Deriving the angle from elapsed
            // time under a TimelineView keeps the phase absolute.
            if isRefreshing, !reduceMotion {
                TimelineView(.animation(minimumInterval: reloadSpinDuration / 30)) { context in
                    reloadSpinnerArc(rotation: reloadSpinAngle(at: context.date))
                }
            } else {
                reloadIdleIcon
            }
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .accessibilityLabel(L("Reload usage"))
        .help(L("Reload usage (⌘R)"))
    }

    private var reloadSpinDuration: TimeInterval { 0.9 }

    private func reloadSpinAngle(at date: Date) -> Angle {
        let elapsed = date.timeIntervalSinceReferenceDate
        let phase = elapsed.truncatingRemainder(dividingBy: reloadSpinDuration) / reloadSpinDuration
        return .degrees(phase * 360)
    }

    private var reloadIdleIcon: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DSColors.inkDim)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }

    /// Spins a true circular arc, about three quarters of a turn. `Circle` is
    /// perfectly symmetric, so no trim angle can drift from the rotation axis.
    private func reloadSpinnerArc(rotation: Angle) -> some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(DSColors.inkDim, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(rotation)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }

    // MARK: - Provider section

    /// One provider's card: a headline (ring, large number, reset) plus the
    /// window rows.
    private func providerSection(
        agentType: AgentType,
        headlineLabel: String,
        rows: [Row],
        trailingLabel: String?,
        note: String?
    ) -> some View {
        VStack(spacing: 0) {
            sectionHeadline(
                agentType: agentType,
                label: headlineLabel,
                trailingLabel: trailingLabel,
                window: rows.first?.window
            )

            if let note {
                HStack {
                    Text(note)
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.inkMute)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 11)
            }

            ForEach(rows) { row in
                Divider().overlay(DSColors.lineFaint)
                windowRow(label: row.label, window: row.window)
            }
        }
        .panelCard()
    }

    /// The section headline: ring on the left, label plus the large 5×7 number
    /// in the middle, reset information on the right.
    private func sectionHeadline(
        agentType: AgentType,
        label: String,
        trailingLabel: String?,
        window: UsageWindow?
    ) -> some View {
        HStack(alignment: .center, spacing: 13) {
            // Always a ring here, even when the setting says numbers. The large
            // 5×7 glyph number sits immediately to the right, so a numeric
            // gauge would print the same value twice, side by side.
            UsageGauge(
                usedPercent: window?.usedPercent,
                agentType: agentType,
                size: s(26),
                forcedStyle: .ring,
                // Stop the spinner once the fetch is done and there is no
                // window — spinning forever looks like an endless wait.
                isUnavailable: snapshot != nil && window == nil
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // The formal label leads with the logo, so which service's
                    // window this is reads at a glance. It is sized to the
                    // adjacent label and centered on the capital letters.
                    AgentMark(agentType: agentType, size: s(8), alignedWithFontSize: s(8))
                    Text("\(agentType.displayName.uppercased()) · \(label)")
                        .font(DSTypography.mono(s(8), weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(DSColors.inkDim)
                    if let trailingLabel {
                        Text(trailingLabel)
                            .font(DSTypography.mono(s(8)))
                            .tracking(0.6)
                            .foregroundStyle(DSColors.inkMute)
                    }
                }

                // The large number is a 5×7 glyph; all numeric glyphs are 5×7.
                HStack(alignment: .bottom, spacing: 4) {
                    if let window {
                        GlyphView(
                            bitmap: Glyph.number(
                                String(Int(window.usedPercent.rounded())),
                                color: color(for: window)
                            )
                        )
                    } else {
                        Text("--")
                            .font(DSTypography.mono(s(11), weight: .semibold))
                            .foregroundStyle(DSColors.inkMute)
                            .alignmentGuide(.bottom) { $0[.firstTextBaseline] }
                    }
                    Text("%")
                        .font(DSTypography.mono(s(9), weight: .semibold))
                        .foregroundStyle(DSColors.inkDim)
                        // A glyph number's bottom edge is its baseline, whereas
                        // text's bottom edge is the descender, so plain .bottom
                        // alignment would leave the % floating by that much.
                        .alignmentGuide(.bottom) { $0[.firstTextBaseline] }
                }
            }

            Spacer(minLength: 0)

            if let resetsAt = window?.resetsAt {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(remainingText(resetsAt))
                        .font(DSTypography.Native.callout(scale, weight: .semibold))
                        .foregroundStyle(DSColors.ink.opacity(0.85))
                    Text(l10n: "Resets \(Self.absoluteResetFormatter.string(from: resetsAt))")
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.inkMute)
                }
            } else if window == nil {
                // No window after a fetch means "unavailable", so stop making
                // the user wait. The reason is explained by the section note.
                Text(l10n: snapshot == nil ? "Loading…" : "Unavailable")
                    .font(DSTypography.mono(s(9)))
                    .foregroundStyle(DSColors.inkMute)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    // MARK: - Window row

    /// One window's row: label, block scale, %, remaining, absolute time.
    ///
    /// `is_active` — the window currently in force — is not shown as a badge.
    /// Which window will stop you is readable from the usage percentages, and a
    /// badge on every row would catch the eye before the scale does. The gauge's
    /// `auto` selection still prioritizes `is_active`.
    private func windowRow(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(DSColors.ink.opacity(0.7))
                .lineLimit(1)
                .frame(width: s(100), alignment: .leading)

            // The scale is a glyph, so its width never shrinks. Where the row is
            // too narrow it gets cut off here rather than pushing the columns to
            // its right off the edge — the % and the remaining time matter more.
            UsageBlockScale(
                usedPercent: window?.usedPercent ?? 0,
                color: window.map { color(for: $0) } ?? DSColors.inkMute
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "--")
                .font(DSTypography.mono(s(10), weight: .semibold))
                .foregroundStyle(window.map { color(for: $0) } ?? DSColors.inkMute)
                .monospacedDigit()
                .frame(width: s(32), alignment: .trailing)

            Text(window?.resetsAt.map { remainingText($0) } ?? "")
                .font(DSTypography.Native.caption(scale))
                .foregroundStyle(DSColors.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: s(78), alignment: .trailing)

            Text(window?.resetsAt.map { Self.absoluteResetFormatter.string(from: $0) } ?? "")
                .font(DSTypography.mono(s(9)))
                .foregroundStyle(DSColors.inkMute)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: s(66), alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(window.map { L("\(Int($0.usedPercent.rounded())) percent") } ?? L("Loading"))
    }

    // MARK: - Daily cost

    /// Estimated daily cost at API rates, shown per agent as a dot chart.
    ///
    /// The dense dot grid made the charts narrow enough to place both agents
    /// **side by side**. Stacked vertically the page would run needlessly long
    /// and make Claude's and Codex's amounts hard to compare.
    @ViewBuilder
    private var costSection: some View {
        let reports: [(agentType: AgentType, report: DailyCostReport?)] = [
            (.claudeCode, dailyCostCoordinator.claude),
            (.codex, dailyCostCoordinator.codex),
        ]
        let available = reports.filter { $0.report?.days.isEmpty == false }

        // No aggregation has returned yet, so this is still loading.
        let isAggregating = reports.allSatisfy { $0.report == nil }

        VStack(alignment: .leading, spacing: 7) {
            // "Cost", "estimated", and the period are common to both cards, so
            // the section heading states them once instead of repeating them
            // per card. Each card says only whose and how much. **It appears
            // during aggregation too** — a heading that shows up later would
            // shift the layout.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: L("Daily cost").uppercased())
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(DSColors.inkDim)
                Text(l10n: "Last \(chartDayCount) days · estimated at API rates")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                Spacer(minLength: 0)
            }
            // Align the left edge with the text inside the cards (padding 12).
            .padding(.leading, 12)

            if isAggregating {
                // Split left and right **per agent even while aggregating**. If
                // one card later broke into two the layout would recompose, so
                // the same skeleton is shown from the start.
                HStack(alignment: .top, spacing: 9) {
                    ForEach(reports, id: \.agentType) { entry in
                        costPlaceholder(agentType: entry.agentType)
                    }
                }
            } else if available.isEmpty {
                HStack {
                    Text(l10n: "No logs found to compute cost from")
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.inkMute)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .panelCard()
            } else {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(available, id: \.agentType) { entry in
                        if let report = entry.report {
                            // Width and height stretching happens inside the
                            // card, before its background is applied.
                            DailyCostCard(
                                agentType: entry.agentType,
                                report: report,
                                dayCount: chartDayCount
                            )
                        }
                    }
                }
            }
        }
    }

    /// The grid shown while aggregating, with a wave traveling left to right
    /// once every 1.4 seconds. Under Reduce Motion it holds still as an
    /// outline-only grid.
    @ViewBuilder
    private var loadingChart: some View {
        let empty = Array(repeating: 0.0, count: chartDayCount)
        if reduceMotion {
            UsageBlockChart(
                values: empty,
                labelFont: DSTypography.mono(s(11)),
                labelFontSize: s(11),
                axisWidth: s(44)
            )
        } else {
            // The animation is discrete — lit dots jump one at a time — so the
            // phase is driven by a TimelineView, the same way `UsageGauge`'s
            // spinner works.
            TimelineView(.animation(minimumInterval: 1.4 / 24)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                UsageBlockChart(
                    values: empty,
                    loadingPhase: elapsed.truncatingRemainder(dividingBy: 1.4) / 1.4,
                    labelFont: DSTypography.mono(s(11)),
                    labelFontSize: s(11),
                    axisWidth: s(44)
                )
            }
        }
    }

    /// The card shown while aggregating. The waving grid says "a chart is coming
    /// here". Showing nothing would leave a gap that reads as broken, and the
    /// height would jump the moment results arrive.
    private func costPlaceholder(agentType: AgentType) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                AgentMark(agentType: agentType, size: s(9), alignedWithFontSize: s(9))
                Text(agentType.displayName.uppercased())
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(DSColors.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(l10n: "Aggregating…")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
            }

            loadingChart
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Daily cost for \(agentType.displayName)"))
        .accessibilityValue(L("Aggregating"))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let extra = snapshot?.claude?.extraUsage, extra.hasContent {
                Text(extraUsageText(extra))
            }
            Spacer(minLength: 0)
            if let fetchedAt = snapshot?.fetchedAt, fetchedAt != .distantPast {
                Text(verbatim: L("Updated \(Self.dateTimeFormatter.string(from: fetchedAt))").uppercased())
            } else {
                Text(verbatim: L("Fetching…").uppercased())
            }
        }
        .font(DSTypography.mono(s(8)))
        .tracking(0.8)
        .foregroundStyle(DSColors.inkMute)
    }

    /// Extra credit: the pay-as-you-go allowance on top. Absent on
    /// subscription-only setups.
    private func extraUsageText(_ extra: ExtraUsageInfo) -> String {
        var parts: [String] = []
        if let used = extra.usedAmount {
            parts.append("\(L("Extra").uppercased()) \(amountText(used, currency: extra.currency))")
        }
        if let limit = extra.limitAmount {
            parts.append("/ \(amountText(limit, currency: extra.currency))")
        }
        if !extra.isEnabled, let reason = extra.disabledReason {
            parts.append("(\(reason.replacingOccurrences(of: "_", with: " ")))")
        }
        return parts.joined(separator: " ")
    }

    private func amountText(_ amount: Double, currency: String?) -> String {
        let symbol = (currency ?? "USD") == "USD" ? "$" : "\(currency ?? "") "
        return amount >= 100
            ? String(format: "%@%.0f", symbol, amount)
            : String(format: "%@%.2f", symbol, amount)
    }

    private func codexAmountText(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? NSDecimalNumber(decimal: amount).stringValue
    }

    // MARK: - Helpers

    /// "2h 10m left". Time remaining conveys the margin more directly, so the
    /// relative form leads and the absolute time sits beside it.
    private func remainingText(_ resetsAt: Date) -> String {
        let seconds = resetsAt.timeIntervalSinceNow
        guard seconds > 0 else { return L("Reset") }
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if days > 0 { return L("\(days)d \(hours)h left") }
        if hours > 0 { return L("\(hours)h \(minutes)m left") }
        return L("\(minutes)m left")
    }

    /// Uses the API's `severity` when it returns one, otherwise decides from
    /// usage-percentage thresholds.
    private func severity(for window: UsageWindow) -> UsageSeverity {
        if let severity = window.severity { return severity }
        switch window.usedPercent {
        case 90...: return .critical
        case 70..<90: return .warning
        default: return .normal
        }
    }

    private func color(for window: UsageWindow) -> Color {
        switch severity(for: window) {
        case .critical: DSColors.signalError
        case .warning: DSColors.signalAlert
        case .normal: DSColors.ink.opacity(0.8)
        }
    }
}
