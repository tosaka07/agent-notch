import AgentNotchCore
import MarkdownUI
import SwiftUI

struct ChatMessageView: View {
    let entry: ChatEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: entry.role == .user ? "person.fill" : "cpu")
                    .font(.system(size: 8))
                Text(entry.role == .user ? "You" : "Claude")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(entry.role == .user ? .blue.opacity(0.8) : .orange.opacity(0.8))

            if !entry.textContent.isEmpty {
                Markdown(entry.textContent)
                    .markdownTheme(AgentNotchMarkdownTheme.theme)
                    .textSelection(.enabled)
            }

            ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.green.opacity(0.6))
                    Text(tool.name)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.8))
                    Text(tool.inputSummary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.role == .user ? Color.white.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MarkdownUI theme is accessed via computed property to avoid concurrency issues
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
                        FontSize(10)
                        ForegroundColor(.white.opacity(0.8))
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
    }
}
