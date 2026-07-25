import AgentNotchCore
import Defaults
import SwiftUI

/// `AskUserQuestion` 用の回答 UI。1-4 問の質問を **Tab 方式** で 1 問ずつ表示する。
/// - 表示領域は常に 1 質問分。高さは質問の内容（選択肢数・テキスト長）に応じて動的に変わる
/// - single-select はオプションをタップすると即座に確定し、左右スライドアニメーションで次の質問へ
/// - multiSelect はオプションをトグルし、下部の確定ボタンで次へ進む
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
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var currentQuestion: AskQuestionInfo.Question { questions[currentIndex] }
    private var isLastQuestion: Bool { currentIndex == questions.count - 1 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = isExpired || context.date >= expiresAt
            VStack(alignment: .leading, spacing: 10) {
                if expired {
                    expiredSection
                } else {
                    progressHeader(now: context.date)

                    ZStack {
                        questionSection(currentQuestion)
                            .id(currentQuestion.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
                                )
                            )
                    }
                    .clipped()

                    navigationFooter
                }
            }
            .padding(12)
            .background(expired ? Color.orange.opacity(0.08) : Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(expired ? Color.orange.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        // banner 表示直後のマウス位置による誤タップ防止（Approve/Deny と同様の意図）。
        .armedAfter()
    }

    /// 応答経路が失効した後の表示。回答はもう届かないため、選択肢の代わりに
    /// ターミナルでの回答を促す（issue #28: 無言失敗の可視化）。
    private var expiredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: s(14)))
                Text("Response window expired")
                    .font(.system(size: s(12), weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            Text("This answer can no longer be delivered. Reply directly in the terminal.")
                .font(.system(size: s(10)))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: s(10), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sub views

    private func progressHeader(now: Date) -> some View {
        HStack(spacing: 6) {
            if questions.count > 1 {
                Button {
                    goToPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: s(10), weight: .bold))
                        .foregroundStyle(currentIndex > 0 ? .white.opacity(0.7) : .white.opacity(0.15))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)
            }

            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: s(14)))

            Text("Claude is asking")
                .font(.system(size: s(12), weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            // 応答期限が近づいたら残り秒数を出す（hook が pass-through に倒れるまでの時間）。
            let remaining = expiresAt.timeIntervalSince(now)
            if remaining < 30, remaining > 0 {
                Text("\(Int(remaining))s")
                    .font(DSTypography.mono(s(10), weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.9))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if questions.count > 1 {
                Text("\(currentIndex + 1)/\(questions.count)")
                    .font(DSTypography.mono(s(10), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    @ViewBuilder
    private func questionSection(_ q: AskQuestionInfo.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let hdr = q.header, !hdr.isEmpty {
                    Text(hdr)
                        .font(.system(size: s(9), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if q.multiSelect {
                    Text("multi")
                        .font(.system(size: s(8), weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.6))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Text(q.question)
                .font(.system(size: s(11)))
                .foregroundStyle(.white.opacity(0.85))

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
                // single-select: タップで即確定し、次の質問へスライド遷移。
                selections[questionId] = [option.label]
                otherInputs[questionId] = ""
                advanceOrSend()
            }
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: selectionIcon(multiSelect: multiSelect, selected: isSelected))
                    .font(.system(size: s(11)))
                    .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.4))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: s(10), weight: .medium))
                        .foregroundStyle(.white)
                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: s(9)))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.22) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func otherRow(questionId: String, multiSelect: Bool) -> some View {
        let binding = Binding<String>(
            get: { otherInputs[questionId] ?? "" },
            set: { otherInputs[questionId] = $0 }
        )
        let hasText = !(otherInputs[questionId] ?? "").isEmpty
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: selectionIcon(multiSelect: multiSelect, selected: hasText))
                .font(.system(size: s(11)))
                .foregroundStyle(hasText ? Color.blue : .white.opacity(0.4))
            TextField("Other…", text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: s(10)))
                .foregroundStyle(.white)
                .onSubmit {
                    advanceOrSend()
                }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hasText ? Color.blue.opacity(0.22) : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var navigationFooter: some View {
        HStack {
            Spacer()
            Button {
                advanceOrSend()
            } label: {
                HStack(spacing: 4) {
                    Text(isLastQuestion ? "Send" : "Next")
                        .font(.system(size: s(10), weight: .semibold))
                    if !isLastQuestion {
                        Image(systemName: "chevron.right")
                            .font(.system(size: s(9), weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(canSend(currentQuestion) ? Color.blue.opacity(0.7) : Color.blue.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!canSend(currentQuestion))
        }
    }

    // MARK: - State management

    private func selectionIcon(multiSelect: Bool, selected: Bool) -> String {
        if multiSelect {
            return selected ? "checkmark.square.fill" : "square"
        } else {
            return selected ? "largecircle.fill.circle" : "circle"
        }
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
            withAnimation(.easeInOut(duration: 0.22)) {
                slideForward = true
                currentIndex += 1
            }
        }
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
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
