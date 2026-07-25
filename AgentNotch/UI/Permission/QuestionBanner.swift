import AgentNotchCore
import Defaults
import SwiftUI

/// `AskUserQuestion` 用の回答 UI。1-4 問の質問を **Tab 方式** で 1 問ずつ表示する。
///
/// 見え方は `PermissionBanner` と揃えてある（詳細画面のタイムラインと地続きに見せるため、
/// system control ではなく黒地 + 細い枠 + mono 大文字 + グリフで組む）。
/// 選択状態もグリフで語る: single-select は ◇/◆、multiSelect は □/■。
/// **notch パネルの中に置かれたもう 1 枚の面**として `notchCard` を被せる
/// （パネルより一段明るい暗色の半透明。詳細は `NotchCard` 参照）。
/// 見出しに状態グリフは置かない（パネル上部のグリフが既に `!` を出しているので、
/// 同じ状態が二重に見えてしまう）。
/// - 表示領域は常に 1 質問分。高さは質問の内容（選択肢数・テキスト長）に応じて動的に変わる
/// - **選択しただけでは次へ進まない**。single-select / multiSelect のどちらも、
///   下部の NEXT / SEND を押して初めて進む（タップ即送信だと押し間違いがそのまま
///   回答として確定してしまい、選び直す機会が無い）
/// - single-select は選択が 1 つに置き換わる。もう一度押すと選択を外せる
/// - Other（自由入力 TextField）は 1 質問分の領域内で機能し、Return または確定ボタンで次へ進む
/// - 全ての質問に回答し終えた時点でまとめて `onAnswer` を呼ぶ（既存の一括送信仕様は変えない）
struct QuestionBanner: View {
    let questions: [AskQuestionInfo.Question]
    /// hook 側の応答待ちが切れる予測時刻。残り時間表示と、ローカルでの失効判定に使う。
    var expiresAt: Date = .distantFuture
    /// 応答経路の失効が確定した（socket 側で pending 破棄済み）。
    var isExpired: Bool = false
    var onAnswer: ([String: [String]]) -> Void
    /// 失効バナーを閉じる。
    var onDismiss: () -> Void = {}

    /// 質問 ID (= question text) → 選択済み label のセット（multiSelect は複数、single は 0 or 1）
    @State private var selections: [String: Set<String>] = [:]
    /// 質問 ID → Other の自由入力テキスト
    @State private var otherInputs: [String: String] = [:]
    /// 現在表示中の質問インデックス
    @State private var currentIndex: Int = 0
    /// true: 次へ（右→左スライド）, false: 前へ（左→右スライド）
    @State private var slideForward = true

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var currentQuestion: AskQuestionInfo.Question { questions[currentIndex] }
    private var isLastQuestion: Bool { currentIndex == questions.count - 1 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = isExpired || context.date >= expiresAt
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                if expired {
                    expiredSection
                } else {
                    progressHeader(now: context.date)

                    ZStack {
                        questionSection(currentQuestion)
                            .id(currentQuestion.id)
                            .transition(slideTransition)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // スライド遷移の最中に隣の質問が横へはみ出すのを確実に切る
                    // （clipped だけだと遷移開始フレームで枠外が見えることがある）。
                    .clipShape(Rectangle())

                    navigationFooter
                }
            }
            .notchCard(accent: expired ? DSColors.signalError : DSColors.signalAlert)
        }
        // banner 表示直後のマウス位置による誤タップ防止（Approve/Deny と同様の意図）。
        .armedAfter()
    }

    /// Reduce Motion 時はスライドせず opacity のみでクロスフェードする。
    private var slideTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// 応答経路が失効した後の表示。回答はもう届かないため、選択肢の代わりに
    /// ターミナルでの回答を促す（issue #28: 無言失敗の可視化）。
    private var expiredSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Text("RESPONSE WINDOW EXPIRED")
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(DSColors.ink.opacity(0.85))
                Spacer(minLength: 0)
            }
            Text("この回答はもう届けられません。ターミナルで直接応答してください。")
                .font(DSTypography.Native.caption(scale))
                .foregroundStyle(DSColors.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                GlyphButton(label: "DISMISS", shortcut: "⏎", isProminent: true) { onDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("この失効バナーを閉じます")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sub views

    /// 見出し行: `‹ QUESTION 2/3 ■▪□ ............ 12S`
    ///
    /// **何問目か（2/3）と進捗（■▪□）は同じことを別の形で言っている**ので隣に置く。
    /// 端に離すと視線が往復するだけで、対応関係も読み取りにくい。
    /// 右端の残り秒だけは別種の情報（応答期限）なので離す。
    private func progressHeader(now: Date) -> some View {
        HStack(spacing: DSSpacing.sm) {
            if questions.count > 1 {
                Button {
                    goToPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: s(9), weight: .semibold))
                        .foregroundStyle(currentIndex == 0 ? DSColors.lineStrong : DSColors.inkDim)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)
                .accessibilityLabel("前の質問")
            }

            Text("QUESTION")
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))

            if questions.count > 1 {
                HStack(spacing: 6) {
                    Text("\(currentIndex + 1)/\(questions.count)")
                        .font(DSTypography.mono(s(9), weight: .semibold))
                        .foregroundStyle(DSColors.inkDim)
                        .monospacedDigit()
                    progressGlyphs
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("質問 \(currentIndex + 1) / \(questions.count)")
            }

            Spacer(minLength: 0)

            // 応答期限が近づいたら残り秒数を出す（hook が pass-through に倒れるまでの時間）。
            let remaining = expiresAt.timeIntervalSince(now)
            if remaining < 30, remaining > 0 {
                Text("\(Int(remaining))S")
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(DSColors.signalAlert)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DSColors.signalAlert.opacity(0.4), lineWidth: 0.5)
                    )
                    .accessibilityLabel("残り \(Int(remaining)) 秒")
            }
        }
    }

    /// 進捗をタスクの語彙（□ 未回答 / ▪ 回答中 / ■ 回答済み）で示す。
    /// 質問を順に片付けていく作業なので、タスクボードと同じ読み方にする。
    private var progressGlyphs: some View {
        HStack(spacing: 3) {
            ForEach(0..<questions.count, id: \.self) { index in
                GlyphView(
                    bitmap: Glyph.task(
                        index < currentIndex ? .done : (index == currentIndex ? .active : .todo),
                        color: index <= currentIndex ? DSColors.ink.opacity(0.8) : DSColors.inkMute
                    ),
                    dot: max(1, s(1.5)),
                    gap: max(0.5, s(0.5))
                )
            }
        }
    }

    @ViewBuilder
    private func questionSection(_ q: AskQuestionInfo.Question) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: 5) {
                if let hdr = q.header, !hdr.isEmpty {
                    Text(hdr.uppercased())
                        .font(DSTypography.mono(s(8), weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(DSColors.inkDim)
                }
                if q.multiSelect {
                    Text("複数選択")
                        .font(DSTypography.mono(s(8)))
                        .tracking(0.6)
                        .foregroundStyle(DSColors.inkMute)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(DSColors.lineDefault, lineWidth: 0.5)
                        )
                }
            }

            // 質問文だけは読み物なので semantic font のまま（mono 大文字にすると読みにくい）。
            Text(q.question)
                .font(DSTypography.Native.callout(scale))
                .foregroundStyle(DSColors.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(q.options) { opt in
                    optionRow(questionId: q.id, option: opt, multiSelect: q.multiSelect)
                }
                // "Other" 行 — 自由入力。入力があると「選ばれた」扱い。
                otherRow(questionId: q.id, multiSelect: q.multiSelect)
            }
        }
    }

    @ViewBuilder
    private func optionRow(questionId: String, option: AskQuestionInfo.Option, multiSelect: Bool) -> some View {
        let isSelected = (selections[questionId] ?? []).contains(option.label)
        Button {
            if multiSelect {
                toggleSelection(questionId: questionId, label: option.label)
            } else {
                // single-select: 選択を 1 つに置き換えるだけ。進むのは NEXT / SEND を
                // 押したときだけにして、選び直す余地を残す。
                if isSelected {
                    selections[questionId] = []
                } else {
                    selections[questionId] = [option.label]
                    otherInputs[questionId] = ""
                }
            }
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                selectionGlyph(multiSelect: multiSelect, selected: isSelected)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(DSTypography.Native.subheadline(scale, weight: .medium))
                        .foregroundStyle(isSelected ? DSColors.ink : DSColors.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(DSTypography.Native.caption(scale))
                            .foregroundStyle(DSColors.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.sm).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DSColors.surfaceStrong : DSColors.canvas)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? DSColors.lineStrong : DSColors.lineFaint, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.description.map { "\(option.label). \($0)" } ?? option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func otherRow(questionId: String, multiSelect: Bool) -> some View {
        let binding = Binding<String>(
            get: { otherInputs[questionId] ?? "" },
            set: { otherInputs[questionId] = $0 }
        )
        let hasText = !(otherInputs[questionId] ?? "").isEmpty
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            selectionGlyph(multiSelect: multiSelect, selected: hasText)
            TextField("その他…", text: binding)
                .textFieldStyle(.plain)
                .font(DSTypography.Native.subheadline(scale))
                .foregroundStyle(DSColors.ink)
                .onSubmit {
                    advanceOrSend()
                }
        }
        .padding(.horizontal, DSSpacing.sm).padding(.vertical, 7)
        .background(hasText ? DSColors.surfaceStrong : DSColors.canvas)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(hasText ? DSColors.lineStrong : DSColors.lineFaint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Other、自由入力")
    }

    private var navigationFooter: some View {
        HStack {
            Spacer()
            // Other の TextField 側にすでに onSubmit(Return) があり、defaultAction を
            // 併用すると Return 1 回で advanceOrSend() が二重発火しうるため、あえて付けない。
            GlyphButton(
                label: isLastQuestion ? "SEND" : "NEXT",
                shortcut: isLastQuestion ? nil : "›",
                tint: DSColors.signalDone,
                isProminent: true,
                isEnabled: canSend(currentQuestion)
            ) {
                advanceOrSend()
            }
        }
    }

    // MARK: - State management

    /// 選択状態をグリフで語る。single-select は ◇/◆、multiSelect は □/■。
    /// 既にタスク（□▪■）と subagent（◆◇）で使っている語彙をそのまま流用し、
    /// 「輪郭 = 未選択 / 塗り = 選択済み」という読み方を画面間で一致させる。
    private func selectionGlyph(multiSelect: Bool, selected: Bool) -> some View {
        let bitmap: GlyphBitmap = multiSelect
            ? Glyph.task(selected ? .done : .todo, color: selected ? DSColors.ink : DSColors.inkDim)
            : (selected ? Glyph.subagentRunning(color: DSColors.ink) : Glyph.subagentIdle(color: DSColors.inkDim))
        return GlyphView(bitmap: bitmap, dot: max(1, s(2)), gap: max(0.5, s(1)))
    }

    private func toggleSelection(questionId: String, label: String) {
        var current = selections[questionId] ?? []
        if current.contains(label) {
            current.remove(label)
        } else {
            current.insert(label)
        }
        selections[questionId] = current
    }

    /// 指定の質問が「いずれかの option が選択済み」OR「Other が入力済み」を満たしているか。
    private func canSend(_ q: AskQuestionInfo.Question) -> Bool {
        let selected = selections[q.id] ?? []
        let other = (otherInputs[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !selected.isEmpty || !other.isEmpty
    }

    /// 次の質問へ進む。最終問なら回答をまとめて送信する。
    private func advanceOrSend() {
        guard canSend(currentQuestion) else { return }
        if isLastQuestion {
            onAnswer(collectedAnswers())
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                slideForward = true
                currentIndex += 1
            }
        }
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            slideForward = false
            currentIndex -= 1
        }
    }

    /// 送信用の answers map を構築。Other は選択肢として配列末尾に追加する。
    private func collectedAnswers() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for q in questions {
            var labels = Array(selections[q.id] ?? [])
            let other = (otherInputs[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !other.isEmpty {
                labels.append(other)
            }
            result[q.question] = labels
        }
        return result
    }
}

#Preview("Question Banner") {
    QuestionBanner(
        questions: [
            .init(
                question: "どのアプローチで進めますか?",
                header: "設計方針",
                multiSelect: false,
                options: [
                    .init(label: "A: 段階的リファクタ", description: "既存 API を維持しつつ内部だけ置き換える", preview: nil),
                    .init(label: "B: 全面書き換え", description: "破壊的変更を許容し、まっさらに作り直す", preview: nil),
                ]
            ),
            .init(
                question: "対象に含めるファイルは?",
                header: nil,
                multiSelect: true,
                options: [
                    .init(label: "PermissionBanner.swift", description: nil, preview: nil),
                    .init(label: "QuestionBanner.swift", description: nil, preview: nil),
                    .init(label: "SessionDetailView.swift", description: nil, preview: nil),
                ]
            ),
        ],
        onAnswer: { _ in }
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}

#Preview("Question Banner (Expired)") {
    QuestionBanner(
        questions: [
            .init(
                question: "どのアプローチで進めますか?",
                header: nil,
                multiSelect: false,
                options: [.init(label: "A", description: nil, preview: nil)]
            ),
        ],
        isExpired: true,
        onAnswer: { _ in },
        onDismiss: {}
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
