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
    var onAnswer: ([String: [String]]) -> Void

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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var scale: CGFloat { textSize.scale }

    private var currentQuestion: AskQuestionInfo.Question { questions[currentIndex] }
    private var isLastQuestion: Bool { currentIndex == questions.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            progressHeader

            ZStack {
                questionSection(currentQuestion)
                    .id(currentQuestion.id)
                    .transition(slideTransition)
            }
            .clipped()

            navigationFooter
        }
        .padding(DSSpacing.md)
        .background(reduceTransparency ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DSColors.signalAlert.opacity(0.35), lineWidth: 1)
        )
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

    // MARK: - Sub views

    private var progressHeader: some View {
        HStack(spacing: DSSpacing.xs) {
            if questions.count > 1 {
                Button {
                    goToPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(currentIndex == 0)
                .accessibilityLabel("前の質問")
            }

            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(DSColors.signalAlert)
                .font(DSTypography.Native.callout(scale))

            Text("Claude is asking")
                .font(DSTypography.Native.headline(scale))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if questions.count > 1 {
                Text("\(currentIndex + 1)/\(questions.count)")
                    .font(DSTypography.Native.monoCaption(scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DSSpacing.xs).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("質問 \(currentIndex + 1) / \(questions.count)")
            }
        }
    }

    @ViewBuilder
    private func questionSection(_ q: AskQuestionInfo.Question) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                if let hdr = q.header, !hdr.isEmpty {
                    Text(hdr)
                        .font(DSTypography.Native.caption2(scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                }
                if q.multiSelect {
                    Text("multi")
                        .font(DSTypography.Native.caption2(scale, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            Text(q.question)
                .font(DSTypography.Native.callout(scale))
                .foregroundStyle(.primary)

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
                    .font(DSTypography.Native.callout(scale))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(DSTypography.Native.subheadline(scale, weight: .medium))
                        .foregroundStyle(.primary)
                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(DSTypography.Native.caption(scale))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.sm).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: selectionIcon(multiSelect: multiSelect, selected: hasText))
                .font(DSTypography.Native.callout(scale))
                .foregroundStyle(hasText ? Color.accentColor : .secondary)
            TextField("Other…", text: binding)
                .textFieldStyle(.plain)
                .font(DSTypography.Native.subheadline(scale))
                .foregroundStyle(.primary)
                .onSubmit {
                    advanceOrSend()
                }
        }
        .padding(.horizontal, DSSpacing.sm).padding(.vertical, 5)
        .background(hasText ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Other、自由入力")
    }

    private var navigationFooter: some View {
        HStack {
            Spacer()
            Button {
                advanceOrSend()
            } label: {
                HStack(spacing: 4) {
                    Text(isLastQuestion ? "Send" : "Next")
                    if !isLastQuestion {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .font(DSTypography.Native.callout(scale, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canSend(currentQuestion))
            // Other の TextField 側にすでに onSubmit(Return) があり、defaultAction を
            // 併用すると Return 1 回で advanceOrSend() が二重発火しうるため、あえて付けない。
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
    .padding(24)
    .frame(width: 360)
    .background(Color.black)
}
