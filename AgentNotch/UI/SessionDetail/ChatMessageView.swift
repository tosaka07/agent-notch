import AgentNotchCore
import MarkdownUI
import SwiftUI

struct ChatMessageView: View {
    let entry: ChatEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Role indicator — thin colored bar
            RoundedRectangle(cornerRadius: 1)
                .fill(entry.role == .user ? Color.blue.opacity(0.5) : Color.orange.opacity(0.4))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 3) {
                // Text content
                if !entry.textContent.isEmpty {
                    Markdown(entry.textContent)
                        .markdownTheme(AgentNotchMarkdownTheme.theme)
                        .textSelection(.enabled)
                }

                // Tool uses — compact inline
                ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                    HStack(spacing: 3) {
                        Text(tool.name)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.6))
                        Text(tool.inputSummary)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}

@MainActor
enum AgentNotchMarkdownTheme {
    static var theme: MarkdownUI.Theme {
        Theme.gitHub
            .text {
                ForegroundColor(.white.opacity(0.8))
                BackgroundColor(nil)
                FontSize(10)
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(9)
                        ForegroundColor(.white.opacity(0.7))
                    }
                    .padding(5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
    }
}
