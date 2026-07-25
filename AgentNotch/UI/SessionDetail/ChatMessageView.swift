import AgentNotchCore
import Defaults
import MarkdownUI
import SwiftUI

struct ChatMessageView: View {
    let entry: ChatEntry

    @Default(.textSize) private var textSize
    private var scale: CGFloat { textSize.scale }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            // Role indicator bar（user/assistant の区別。DSColors の signal 色とは別軸）
            RoundedRectangle(cornerRadius: 1)
                .fill(entry.role == .user ? Color.accentColor.opacity(0.6) : Color.orange.opacity(0.5))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                if !entry.textContent.isEmpty {
                    Markdown(entry.textContent)
                        .markdownTheme(AgentNotchMarkdownTheme.theme(scale: scale))
                        .textSelection(.enabled)
                }

                ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                    HStack(spacing: 4) {
                        Text(tool.name)
                            .font(DSTypography.Native.monoCaption(scale, weight: .medium))
                            .foregroundStyle(DSColors.signalDone)
                        Text(tool.inputSummary)
                            .font(DSTypography.Native.monoCaption(scale))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.role == .user ? "ユーザー" : "アシスタント")
    }
}

@MainActor
enum AgentNotchMarkdownTheme {
    static func theme(scale: CGFloat = 1.0) -> MarkdownUI.Theme {
        let bodySize = (11 * scale * 2).rounded() / 2
        let codeSize = (9 * scale * 2).rounded() / 2
        return Theme.gitHub
            .text {
                ForegroundColor(.primary.opacity(0.9))
                BackgroundColor(nil)
                FontSize(bodySize)
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(codeSize)
                        ForegroundColor(.primary.opacity(0.8))
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
    }
}

#Preview("Chat Message") {
    VStack(alignment: .leading, spacing: 2) {
        ChatMessageView(entry: ChatEntry(role: .user, textContent: "サーバーの起動スクリプトを直して"))
        ChatMessageView(entry: ChatEntry(
            role: .assistant,
            textContent: "`scripts/start.sh` の権限を修正しました。",
            toolUses: [.init(name: "Bash", inputSummary: "chmod +x scripts/start.sh")]
        ))
    }
    .padding(16)
    .frame(width: 320)
    .background(Color.black)
}
