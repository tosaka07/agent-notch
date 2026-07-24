import AgentNotchCore
import Defaults
import SwiftUI

/// `AskUserQuestion` 用の回答 UI。1-4 問の質問を縦に並べ、各質問は
/// - options（label + description のタップ可能行。multiSelect はチェック式、single はラジオ式）
/// - Other (自由入力 TextField) を末尾に自動追加
/// すべての質問に回答（option 選択 or Other 入力のどちらか）したら Send が有効化する。
struct QuestionBanner: View {
    let questions: [AskQuestionInfo.Question]
    var onAnswer: ([String: [String]]) -> Void

    /// 質問 ID (= question text) → 選択済み label のセット（multiSelect は複数、single は 0 or 1）
    @State private var selections: [String: Set<String>] = [:]
    /// 質問 ID → Other の自由入力テキスト
    @State private var otherInputs: [String: String] = [:]

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(questions) { q in
                questionSection(q)
            }

            sendButton
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Sub views

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: s(14)))
            Text(questions.count > 1 ? "Claude is asking (\(questions.count))" : "Claude is asking")
                .font(.system(size: s(12), weight: .semibold))
                .foregroundStyle(.white)
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
            toggleSelection(questionId: questionId, label: option.label, multiSelect: multiSelect)
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
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hasText ? Color.blue.opacity(0.22) : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var sendButton: some View {
        HStack {
            Spacer()
            Button {
                onAnswer(collectedAnswers())
            } label: {
                Text("Send")
                    .font(.system(size: s(10), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(canSend ? Color.blue.opacity(0.7) : Color.blue.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .armedAfter()
    }

    // MARK: - State management

    private func selectionIcon(multiSelect: Bool, selected: Bool) -> String {
        if multiSelect {
            return selected ? "checkmark.square.fill" : "square"
        } else {
            return selected ? "largecircle.fill.circle" : "circle"
        }
    }

    private func toggleSelection(questionId: String, label: String, multiSelect: Bool) {
        var current = selections[questionId] ?? []
        if multiSelect {
            if current.contains(label) {
                current.remove(label)
            } else {
                current.insert(label)
            }
        } else {
            // single-select: クリックすると Other の入力はクリアして排他に
            if current.contains(label) {
                current.removeAll()
            } else {
                current = [label]
                otherInputs[questionId] = ""
            }
        }
        selections[questionId] = current
    }

    /// 全ての質問で「いずれかの option が選択済み」OR「Other が入力済み」を満たしているか。
    private var canSend: Bool {
        for q in questions {
            let selected = selections[q.id] ?? []
            let other = otherInputs[q.id] ?? ""
            if selected.isEmpty && other.isEmpty { return false }
        }
        return true
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
