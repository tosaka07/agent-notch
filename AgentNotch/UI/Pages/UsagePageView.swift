import AgentNotchCore
import Defaults
import SwiftUI

/// `usage` モードの UI。使用量（USAGE）の全内訳ページ。
///
/// 一覧トップバー左翼の `UsageGauge` をクリックして開く。左翼のゲージが「今どれくらいか」の
/// 一点情報しか見せないのに対し、こちらは取得できている情報を全て出す:
/// - Claude Code: current session（5h 枠）/ current week (all models) / モデル別の週次枠（全件）
/// - Codex: 5h window / weekly window / プラン種別
/// - 各ウィンドウの使用率・残り時間・リセット時刻、スナップショットの取得時刻
///
/// # 表現
/// notch の翼と同じ「独自言語」側の画面として、使用率は `PixelBar`（幅いっぱいに敷き詰めた
/// ドットの帯）で描く。各ウィンドウの見出し左には `UsageGauge`（ピクセルのリング/数字）を置き、
/// 一覧トップバーで見ていた形がここでも出てくるようにしている。
///
/// 初回ポーリングが返る前は「何も表示されない」と壊れて見えるため、ウィンドウ枠の
/// プレースホルダ（輪郭だけのゲージ + 空のバー）を出す。
struct UsagePageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var usageCoordinator: UsageCoordinator
    @ObservedObject var dailyCostCoordinator: DailyCostCoordinator

    @Default(.textSize) private var textSize

    /// bar chart に出す日数。
    private let chartDayCount = 14

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// 内容の左右余白。notch パネルの角丸に食われないよう十分に取る。
    private let contentPadding: CGFloat = 20

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var snapshot: UsageSnapshot? { usageCoordinator.snapshot }

    /// 1 ウィンドウ分の表示データ。取得前は `window` が nil のプレースホルダとして使う。
    private struct Row: Identifiable {
        let id: String
        let label: String
        let window: UsageWindow?
    }

    private var claudeRows: [Row] {
        guard let claude = snapshot?.claude else {
            return [
                Row(id: "session", label: "CURRENT SESSION", window: nil),
                Row(id: "week", label: "CURRENT WEEK (ALL MODELS)", window: nil),
            ]
        }
        var rows: [Row] = []
        if let session = claude.session {
            rows.append(Row(id: "session", label: "CURRENT SESSION", window: session))
        }
        if let week = claude.weekAllModels {
            rows.append(Row(id: "week", label: "CURRENT WEEK (ALL MODELS)", window: week))
        }
        for model in claude.weekModels {
            rows.append(
                Row(
                    id: "week-\(model.modelLabel)",
                    label: "CURRENT WEEK (\(model.modelLabel.uppercased()))",
                    window: model.window
                )
            )
        }
        return rows
    }

    private var codexRows: [Row] {
        guard let codex = snapshot?.codex else { return [] }
        var rows: [Row] = []
        if let primary = codex.primary {
            rows.append(Row(id: "codex-5h", label: "5H WINDOW", window: primary))
        }
        if let secondary = codex.secondary {
            rows.append(Row(id: "codex-week", label: "WEEKLY WINDOW", window: secondary))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    agentSection(
                        agentType: .claudeCode,
                        rows: claudeRows,
                        trailingLabel: nil,
                        emptyNote: snapshot?.claude == nil && snapshot != nil
                            ? "使用量を取得できませんでした"
                            : nil
                    )

                    if let codex = snapshot?.codex {
                        agentSection(
                            agentType: .codex,
                            rows: codexRows,
                            trailingLabel: codex.planType?.uppercased(),
                            emptyNote: codexRows.isEmpty ? "従量課金プランのため rate limit なし" : nil
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
    }

    // MARK: - Top bar

    /// 物理 notch の高さ分のスペースを取りつつ、左翼に戻るボタン、右翼にタイトルを置く。
    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.backToList()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DSColors.inkDim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("一覧に戻る")
            .padding(.leading, contentPadding - 8)

            Spacer()

            Text("USAGE")
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DSColors.inkDim)
                .padding(.trailing, contentPadding)
        }
        .frame(height: viewModel.physicalNotchHeight + 4)
    }

    // MARK: - Sections

    /// セクションの外枠。見出しが並ぶだけでは切れ目が読めないので、
    /// 背景（`DSColors.surface`）+ 枠線 + 左端のアクセントバーで塊として見せる。
    private func sectionCard<Content: View>(
        accent: Color,
        title: String,
        titleColor: Color,
        trailingLabel: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // 左端のアクセントバー。どのセクションかを色で一目で分かるようにする。
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(DSTypography.mono(s(10), weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(titleColor)

                    if let trailingLabel {
                        Text(trailingLabel)
                            .font(DSTypography.mono(s(8)))
                            .tracking(0.4)
                            .foregroundStyle(DSColors.inkMute)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DSColors.surfaceStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer(minLength: 0)
                }

                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DSColors.lineDefault, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func agentSection(
        agentType: AgentType,
        rows: [Row],
        trailingLabel: String?,
        emptyNote: String?
    ) -> some View {
        sectionCard(
            accent: agentType.color,
            title: agentType.displayName.uppercased(),
            titleColor: agentType.color,
            trailingLabel: trailingLabel
        ) {
            if let emptyNote {
                Text(emptyNote)
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
            }

            ForEach(rows) { row in
                windowRow(agentType: agentType, label: row.label, window: row.window)
            }

            if agentType == .claudeCode, let extra = snapshot?.claude?.extraUsage, extra.hasContent {
                Divider().overlay(DSColors.lineFaint)
                extraUsageRow(extra)
            }
        }
    }

    /// 追加クレジット（従量課金の上乗せ枠）。サブスクのみの環境では非表示になる。
    private func extraUsageRow(_ extra: ExtraUsageInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("EXTRA CREDITS")
                    .font(DSTypography.mono(s(8)))
                    .tracking(0.4)
                    .foregroundStyle(DSColors.inkDim)
                Spacer(minLength: 0)
                if let used = extra.usedAmount {
                    Text(amountText(used, currency: extra.currency))
                        .font(DSTypography.mono(s(10), weight: .semibold))
                        .foregroundStyle(DSColors.ink)
                        .fixedSize()
                }
            }

            if let percent = extra.usedPercent, extra.limitAmount != nil {
                PixelBar(usedPercent: percent, color: barColor(for: percent), trackColor: DSColors.inkGhost)
            }

            HStack(spacing: 6) {
                if let limit = extra.limitAmount {
                    Text("LIMIT \(amountText(limit, currency: extra.currency))")
                }
                if let balance = extra.balanceAmount {
                    Text("BALANCE \(amountText(balance, currency: extra.currency))")
                }
                if !extra.isEnabled, let reason = extra.disabledReason {
                    Text("DISABLED (\(reason.replacingOccurrences(of: "_", with: " ")))")
                }
                Spacer(minLength: 0)
            }
            .font(DSTypography.mono(s(8)))
            .foregroundStyle(DSColors.inkMute)
        }
    }

    private func amountText(_ amount: Double, currency: String?) -> String {
        let symbol = (currency ?? "USD") == "USD" ? "$" : "\(currency ?? "") "
        return amount >= 100
            ? String(format: "%@%.0f", symbol, amount)
            : String(format: "%@%.2f", symbol, amount)
    }

    /// 1 ウィンドウ分。ゲージ + ラベル + 幅いっぱいのドットバー + 使用率 + リセット情報。
    /// `window` が nil のときはプレースホルダ（取得中）として描く。
    private func windowRow(agentType: AgentType, label: String, window: UsageWindow?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            UsageGauge(
                usedPercent: window?.usedPercent,
                agentType: agentType,
                size: s(26)
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(DSTypography.mono(s(8)))
                        .tracking(0.4)
                        .foregroundStyle(DSColors.inkDim)
                        .lineLimit(1)

                    // API が「今この枠が効いている」と言っている枠を明示する
                    // （session より先にモデル別週次枠が上限に当たっているケースがあるため）。
                    if window?.isActive == true {
                        Text("ACTIVE")
                            .font(DSTypography.mono(s(7), weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(DSColors.signalAlert)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(DSColors.signalAlert.opacity(0.5), lineWidth: 1)
                            )
                            .fixedSize()
                    }

                    Spacer(minLength: 0)

                    if let window {
                        Text("\(Int(window.usedPercent.rounded()))%")
                            .font(DSTypography.mono(s(11), weight: .semibold))
                            .foregroundStyle(barColor(for: window.usedPercent, severity: window.severity))
                            .fixedSize()
                    } else {
                        Text("--")
                            .font(DSTypography.mono(s(11), weight: .semibold))
                            .foregroundStyle(DSColors.inkMute)
                            .fixedSize()
                    }
                }

                PixelBar(
                    usedPercent: window?.usedPercent ?? 0,
                    color: barColor(for: window?.usedPercent ?? 0, severity: window?.severity),
                    trackColor: DSColors.inkGhost
                )

                if let resetsAt = window?.resetsAt {
                    Text(resetsCaption(resetsAt))
                        .font(DSTypography.mono(s(8)))
                        .foregroundStyle(DSColors.inkMute)
                } else if window == nil {
                    Text("取得中…")
                        .font(DSTypography.mono(s(8)))
                        .foregroundStyle(DSColors.inkMute)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(
            window.map { "\(Int($0.usedPercent.rounded()))パーセント" } ?? "取得中"
        )
    }

    // MARK: - Daily cost chart

    /// 日毎の推定コスト（API 換算）。Claude / Codex を別チャートで縦に並べる。
    @ViewBuilder
    private var costSection: some View {
        let reports: [(agentType: AgentType, report: DailyCostReport?)] = [
            (.claudeCode, dailyCostCoordinator.claude),
            (.codex, dailyCostCoordinator.codex),
        ]

        sectionCard(
            accent: DSColors.signalDone,
            title: "DAILY COST",
            titleColor: DSColors.inkDim,
            trailingLabel: "API 換算推定"
        ) {
            ForEach(reports.filter { ($0.report?.days.isEmpty == false) }, id: \.agentType) { entry in
                if let report = entry.report {
                    costChart(agentType: entry.agentType, report: report)
                }
            }

            if reports.allSatisfy({ $0.report == nil }) {
                Text("集計中…")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
            } else if reports.allSatisfy({ $0.report?.days.isEmpty ?? true }) {
                Text("コストを算出できるログが見つかりませんでした")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
            }
        }
    }

    private func costChart(agentType: AgentType, report: DailyCostReport) -> some View {
        let days = report.recentDaysFilled(count: chartDayCount)
        let values = days.map(\.estimatedCostUSD)
        let peak = values.max() ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(agentType.displayName.uppercased())
                    .font(DSTypography.mono(s(8), weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(agentType.color)
                Text("直近\(chartDayCount)日")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                Spacer(minLength: 0)
                Text(CostCalculator.formatCost(values.reduce(0, +)))
                    .font(DSTypography.mono(s(11), weight: .semibold))
                    .foregroundStyle(DSColors.ink)
                    .fixedSize()
            }

            PixelBarChart(
                values: values,
                barColors: values.map { value in
                    // 最大値に近い日を強調して「どこが重かったか」が一目で分かるようにする。
                    guard peak > 0 else { return DSColors.inkGhost }
                    let ratio = value / peak
                    return ratio >= 0.9
                        ? DSColors.signalAlert
                        : (ratio >= 0.5 ? DSColors.ink : DSColors.inkDim)
                }
            )
            .accessibilityElement()
            .accessibilityLabel("\(agentType.displayName) の日毎コスト")
            .accessibilityValue("直近\(chartDayCount)日で \(CostCalculator.formatCost(values.reduce(0, +)))")

            HStack(spacing: 0) {
                Text(dayLabel(days.first?.day))
                Spacer(minLength: 0)
                if peak > 0 {
                    Text("PEAK \(CostCalculator.formatCost(peak))")
                }
                Spacer(minLength: 0)
                Text(dayLabel(days.last?.day))
            }
            .font(DSTypography.mono(s(8)))
            .foregroundStyle(DSColors.inkMute)

            if !report.unsupportedModels.isEmpty {
                Text("単価未対応で除外: \(report.unsupportedModels.joined(separator: ", "))")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayLabel(_ day: Date?) -> String {
        guard let day else { return "" }
        return Self.dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    private var footer: some View {
        HStack(spacing: 8) {
            if let fetchedAt = snapshot?.fetchedAt, fetchedAt != .distantPast {
                Text("UPDATED \(Self.dateTimeFormatter.string(from: fetchedAt))")
                    .font(DSTypography.mono(s(8)))
                    .tracking(0.4)
                    .foregroundStyle(DSColors.inkMute)
            } else {
                Text("FETCHING…")
                    .font(DSTypography.mono(s(8)))
                    .tracking(0.4)
                    .foregroundStyle(DSColors.inkMute)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    /// 「あと 2 時間でリセット（14:00）」のようなキャプション。
    /// 残り時間の方が「今どれだけ猶予があるか」を掴みやすいので、相対表現を先に出す。
    private func resetsCaption(_ resetsAt: Date) -> String {
        let absolute = Self.timeFormatter.string(from: resetsAt)
        guard resetsAt > .now else { return "RESETS \(absolute)" }
        let relative = Self.relativeFormatter.localizedString(for: resetsAt, relativeTo: .now)
        return "RESETS \(relative)（\(absolute)）"
    }

    /// バー・数字の色。API が `severity` を返している場合はそちらを優先し、
    /// 無ければ使用率のしきい値（70%/90%）で判断する。
    private func barColor(for percent: Double, severity: UsageSeverity? = nil) -> Color {
        switch severity {
        case .critical: return DSColors.signalError
        case .warning: return DSColors.signalAlert
        case .normal: return DSColors.ink
        case nil:
            switch percent {
            case 90...: return DSColors.signalError
            case 70..<90: return DSColors.signalAlert
            default: return DSColors.ink
            }
        }
    }
}
