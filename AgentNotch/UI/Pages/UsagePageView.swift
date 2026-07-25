import AgentNotchCore
import Defaults
import SwiftUI

/// `usage` モードの UI。使用量（USAGE）の全内訳ページ（Claude Design モック 3b / 2b）。
///
/// 一覧トップバー左翼の `UsageGauge` をクリックして開く。左翼のゲージが「今どれくらいか」の
/// 一点情報しか見せないのに対し、こちらは取得できている情報を全て出す。
///
/// # 構造（モック 3b）
/// ```
/// ┌─ CLAUDE ─────────────────────────────────────────────┐
/// │ ◯  CLAUDE · 現在のセッション    あと 2 時間 10 分      │
/// │    48%（5×7 グリフ）            今日 23:14 リセット    │
/// ├──────────────────────────────────────────────────────┤
/// │ SESSION  NOW  ■■■■■□□□□□  48%  あと2時間  23:14      │
/// │ WEEKLY        ■■■■■■□□□□  62%  あと2日    7/28 09:00 │
/// └──────────────────────────────────────────────────────┘
/// ```
/// **プロバイダ単位でセクションを分け**、SESSION / WEEKLY / モデル別が Claude 固有で
/// あることを構造で示す。目盛りはグリフ辞書の D（3×3 ブロック 10 個 = 100%）。
///
/// 初回ポーリングが返る前は「何も表示されない」と壊れて見えるため、
/// プレースホルダ（輪郭だけのゲージ + 空の目盛り）を出す。
struct UsagePageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var usageCoordinator: UsageCoordinator
    @ObservedObject var dailyCostCoordinator: DailyCostCoordinator

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// bar chart に出す日数。
    private let chartDayCount = 14
    /// 内容の左右余白。notch パネルの角丸に食われないよう十分に取る。
    private let contentPadding: CGFloat = 20

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }
    private var scale: CGFloat { textSize.scale }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let absoluteResetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md HH:mm")
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
                Row(id: "session", label: "SESSION", window: nil),
                Row(id: "week", label: "WEEKLY", window: nil),
            ]
        }
        var rows: [Row] = []
        if let session = claude.session {
            rows.append(Row(id: "session", label: "SESSION", window: session))
        }
        if let week = claude.weekAllModels {
            rows.append(Row(id: "week", label: "WEEKLY", window: week))
        }
        for model in claude.weekModels {
            rows.append(
                Row(
                    id: "week-\(model.modelLabel)",
                    label: "\(model.modelLabel.uppercased()) WEEKLY",
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
            rows.append(Row(id: "codex-week", label: "WEEKLY", window: secondary))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    providerSection(
                        agentType: .claudeCode,
                        headlineLabel: "現在のセッション",
                        rows: claudeRows,
                        trailingLabel: nil,
                        emptyNote: snapshot != nil && snapshot?.claude == nil
                            ? "使用量を取得できませんでした"
                            : nil
                    )

                    if let codex = snapshot?.codex {
                        providerSection(
                            agentType: .codex,
                            headlineLabel: "現在の 5 時間枠",
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
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))
                .padding(.trailing, contentPadding)
        }
        .frame(height: viewModel.physicalNotchHeight + 4)
    }

    // MARK: - Provider section

    /// プロバイダ 1 つ分のカード。見出し（リング + 大きい数字 + リセット）+ ウィンドウ行。
    private func providerSection(
        agentType: AgentType,
        headlineLabel: String,
        rows: [Row],
        trailingLabel: String?,
        emptyNote: String?
    ) -> some View {
        VStack(spacing: 0) {
            sectionHeadline(
                agentType: agentType,
                label: headlineLabel,
                trailingLabel: trailingLabel,
                window: rows.first?.window
            )

            if let emptyNote {
                HStack {
                    Text(emptyNote)
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
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(sectionBorder(rows: rows), lineWidth: 0.5)
        )
    }

    /// 危険域の枠だけ縁取りを強める（モック 3b の Codex カードが赤枠になっているのと同じ意図）。
    private func sectionBorder(rows: [Row]) -> Color {
        let severities = rows.compactMap(\.window).map { severity(for: $0) }
        if severities.contains(.critical) { return DSColors.signalError.opacity(0.3) }
        if severities.contains(.warning) { return DSColors.signalAlert.opacity(0.25) }
        return DSColors.lineDefault
    }

    /// セクション見出し。左にリング、中央にラベル + 5×7 の大きい数字、右にリセット情報。
    private func sectionHeadline(
        agentType: AgentType,
        label: String,
        trailingLabel: String?,
        window: UsageWindow?
    ) -> some View {
        HStack(alignment: .center, spacing: 13) {
            // ここは設定が「数字」でもリング固定。すぐ右に 5×7 グリフの大きい数字が出るので、
            // ゲージまで数字にすると同じ値が並んで出てしまう。
            UsageGauge(
                usedPercent: window?.usedPercent,
                agentType: agentType,
                size: s(26),
                forcedStyle: .ring,
                // 取得済みで枠が無いならスピナーを止める（回り続けると永久に待たされて見える）。
                isUnavailable: snapshot != nil && window == nil
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // 正式表記のラベルには先頭にロゴを置く（どのサービスの枠か一目で分かる）。
                    // サイズは隣のラベルに合わせ、重心も文字の大文字に揃える。
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

                // 大きい数字は 5×7 グリフ（数値グリフは 5×7 に一本化）。
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
                        // グリフの数字は下端がベースライン。テキストは下端がディセンダなので、
                        // .bottom 揃えのままだと % がその分だけ浮いて見える。
                        .alignmentGuide(.bottom) { $0[.firstTextBaseline] }
                }
            }

            Spacer(minLength: 0)

            if let resetsAt = window?.resetsAt {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(remainingText(resetsAt))
                        .font(DSTypography.Native.callout(scale, weight: .semibold))
                        .foregroundStyle(DSColors.ink.opacity(0.85))
                    Text("\(Self.absoluteResetFormatter.string(from: resetsAt)) リセット")
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.inkMute)
                }
            } else if window == nil {
                // 取得を試みた後に枠が無いのは「取得できない」の意味なので、待たせ続けない。
                // 理由（従量課金 / 取得失敗）はセクション内の emptyNote 側で説明する。
                Text(snapshot == nil ? "取得中…" : "取得なし")
                    .font(DSTypography.mono(s(9)))
                    .foregroundStyle(DSColors.inkMute)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    // MARK: - Window row

    /// 1 ウィンドウ分の行: ラベル + ブロック目盛り + % + 残り + 絶対時刻。
    ///
    /// `is_active`（いま効いている枠）はバッジとしては出さない。どの枠で止まるかは
    /// 使用率を見れば読めるので、行ごとにバッジが付くと目盛りより先に目を引いてしまう。
    /// ゲージの `auto` 選択では引き続き `is_active` を優先している。
    private func windowRow(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(DSColors.ink.opacity(0.7))
                .lineLimit(1)
                .frame(width: s(100), alignment: .leading)

            // 目盛りはグリフなので幅が縮まない。行幅が足りない環境では右の列を押し出す代わりに
            // ここで切り落とす（% や残り時間の方が情報として優先度が高い）。
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
        .accessibilityValue(window.map { "\(Int($0.usedPercent.rounded()))パーセント" } ?? "取得中")
    }

    // MARK: - Daily cost

    /// 日毎の推定コスト（API 換算）。エージェント別にドットチャートで出す。
    ///
    /// チャートを密なドット格子にして横幅が縮んだので、エージェント 2 つ分を**横並び**に
    /// する。縦に積むとページが無駄に長くなり、Claude と Codex の額を見比べにくい。
    @ViewBuilder
    private var costSection: some View {
        let reports: [(agentType: AgentType, report: DailyCostReport?)] = [
            (.claudeCode, dailyCostCoordinator.claude),
            (.codex, dailyCostCoordinator.codex),
        ]
        let available = reports.filter { $0.report?.days.isEmpty == false }

        // まだ 1 つも集計が返っていない = ローディング中。
        let isAggregating = reports.allSatisfy { $0.report == nil }

        VStack(alignment: .leading, spacing: 7) {
            // 「COST」「推定」「期間」はどちらのカードにも共通なので、カードごとに
            // 繰り返さずセクションの見出しに 1 度だけ出す。カードは「誰の・いくら」だけを言う。
            // **集計中でも出す**（後から見出しが増えると版面が飛ぶ）。
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("DAILY COST")
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(DSColors.inkDim)
                Text("直近 \(chartDayCount) 日 · API 換算の推定")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
                Spacer(minLength: 0)
            }
            // カード内の文字（padding 12）と左端を揃える。
            .padding(.leading, 12)

            if isAggregating {
                // 集計中も**エージェントごとに左右に分ける**。あとからカードが 2 枚に
                // 割れると版面が組み替わるので、最初から同じ骨格を見せる。
                HStack(alignment: .top, spacing: 9) {
                    ForEach(reports, id: \.agentType) { entry in
                        costPlaceholder(agentType: entry.agentType)
                    }
                }
            } else if available.isEmpty {
                HStack {
                    Text("コストを算出できるログが見つかりませんでした")
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.inkMute)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(DSColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(available, id: \.agentType) { entry in
                        if let report = entry.report {
                            // 幅・高さの引き伸ばしはカード側（背景を敷く前）で行う。
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

    /// 集計中の格子。波が左から右へ流れる（1 周 1.4 秒）。
    /// Reduce Motion では動かさず、輪郭だけの静止した格子にする。
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
            // ドット単位で点灯が飛ぶ離散アニメーションなので TimelineView で位相を送る
            // （`UsageGauge` のスピナーと同じ方式）。
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

    /// 集計中のカード。波が流れる格子を出して「ここにチャートが来る」ことを示す。
    /// 何も出さないと版面が空いて壊れて見え、結果が入った瞬間に高さが飛ぶ。
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
                Text("集計中…")
                    .font(DSTypography.mono(s(8)))
                    .foregroundStyle(DSColors.inkMute)
            }

            loadingChart
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DSColors.lineDefault, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agentType.displayName) の日毎コスト")
        .accessibilityValue("集計中")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let extra = snapshot?.claude?.extraUsage, extra.hasContent {
                Text(extraUsageText(extra))
            }
            Spacer(minLength: 0)
            if let fetchedAt = snapshot?.fetchedAt, fetchedAt != .distantPast {
                Text("UPDATED \(Self.dateTimeFormatter.string(from: fetchedAt))")
            } else {
                Text("FETCHING…")
            }
        }
        .font(DSTypography.mono(s(8)))
        .tracking(0.8)
        .foregroundStyle(DSColors.inkMute)
    }

    /// 追加クレジット（従量課金の上乗せ枠）。サブスクのみの環境では出ない。
    private func extraUsageText(_ extra: ExtraUsageInfo) -> String {
        var parts: [String] = []
        if let used = extra.usedAmount {
            parts.append("EXTRA \(amountText(used, currency: extra.currency))")
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

    // MARK: - Helpers

    /// 「あと 2 時間 10 分」。残り時間の方が猶予を掴みやすいので相対を主にし、絶対時刻は隣に出す。
    private func remainingText(_ resetsAt: Date) -> String {
        let seconds = resetsAt.timeIntervalSinceNow
        guard seconds > 0 else { return "リセット済み" }
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if days > 0 { return "あと \(days) 日 \(hours) 時間" }
        if hours > 0 { return "あと \(hours) 時間 \(String(format: "%02d", minutes)) 分" }
        return "あと \(minutes) 分"
    }

    /// API が `severity` を返していればそれを使い、無ければ使用率のしきい値で判断する。
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
