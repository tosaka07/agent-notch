import AgentNotchCore
import Defaults
import SwiftUI

struct QuestionBanner: View {
    let question: String
    let options: [String]
    var onAnswer: (String) -> Void

    @State private var textAnswer = ""
    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: s(14)))
                Text("Claude is asking")
                    .font(.system(size: s(12), weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(question)
                .font(.system(size: s(11)))
                .foregroundStyle(.white.opacity(0.85))

            if options.isEmpty {
                HStack {
                    TextField("Type your answer...", text: $textAnswer)
                        .textFieldStyle(.plain)
                        .font(.system(size: s(11)))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button { onAnswer(textAnswer) } label: {
                        Text("Send")
                            .font(.system(size: s(10), weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.blue.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(textAnswer.isEmpty)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(options, id: \.self) { option in
                        Button { onAnswer(option) } label: {
                            Text(option)
                                .font(.system(size: s(10), weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
    }
}
