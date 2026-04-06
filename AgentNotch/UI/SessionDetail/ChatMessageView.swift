import AgentNotchCore
import MarkdownUI
import SwiftUI

struct ChatMessageView: View {
    let entry: ChatEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Role indicator bar
            RoundedRectangle(cornerRadius: 1)
                .fill(entry.role == .user ? Color.blue.opacity(0.6) : Color.orange.opacity(0.5))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                if !entry.textContent.isEmpty {
                    Markdown(entry.textContent)
                        .markdownTheme(AgentNotchMarkdownTheme.theme)
                        .textSelection(.enabled)
                }

                ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                    HStack(spacing: 4) {
                        Text(tool.name)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))
                        Text(tool.inputSummary)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
    }
}

@MainActor
enum AgentNotchMarkdownTheme {
    static var theme: MarkdownUI.Theme {
        Theme.gitHub
            .text {
                ForegroundColor(.white.opacity(0.85))
                BackgroundColor(nil)
                FontSize(11)
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(9)
                        ForegroundColor(.white.opacity(0.75))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
    }
}
