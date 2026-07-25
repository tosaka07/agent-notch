import AgentNotchCore
import Defaults
import MarkdownUI
import SwiftUI

/// タイムラインに出す発言 1 件（モック 3a）。
///
/// # 形
/// `ToolLogRow` と**同じ 1 行ヘッダー + インデントした中身**の構造にする。
/// 左のドットが縦に揃うので、発言とツール実行が混ざっても 1 本のタイムラインとして読める。
///
/// ```
/// ● 21:04:02  YOU
///     サーバーの起動スクリプトを直して
///
/// ● 21:04:07  CLAUDE CODE
///     `scripts/start.sh` の権限を修正しました。
/// ```
///
/// 発言者は**ドットの色とラベル**で示す（自分 = 白、エージェント = エージェント色）。
/// 以前は左に 2pt の縦バーを立てて accentColor / orange で塗っていたが、
/// タイムラインの他の行と語彙が合わず、チャットだけ別の UI に見えていた。
struct ChatMessageView: View {
    let entry: ChatEntry
    /// 発言者ラベルとドットの色に使う。nil ならエージェント非依存の中立色。
    var agentType: AgentType?

    @Default(.textSize) private var textSize
    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var isUser: Bool { entry.role == .user }

    /// 発言者の色。ツールログのドット（白 / cyan / 緑 …）と衝突しないよう、
    /// 自分は白、エージェントはエージェント識別色に寄せる。
    private var roleColor: Color {
        isUser ? DSColors.ink.opacity(0.75) : (agentType?.color ?? DSColors.signalThinking)
    }

    private var roleLabel: String {
        isUser ? "YOU" : (agentType?.displayName.uppercased() ?? "AGENT")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerLine

            VStack(alignment: .leading, spacing: 4) {
                if !entry.textContent.isEmpty {
                    Markdown(entry.textContent)
                        .markdownTheme(AgentNotchMarkdownTheme.theme(scale: scale))
                        .textSelection(.enabled)
                }

                ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                    // ツール実行の行（ToolLogRow）と同じ見え方にして、
                    // transcript 側から拾った tool_use も同じものとして読めるようにする。
                    HStack(spacing: 6) {
                        Text("▸")
                            .foregroundStyle(DSColors.inkMute)
                        Text(tool.name.uppercased())
                            .foregroundStyle(DSColors.ink.opacity(0.7))
                        Text(tool.inputSummary)
                            .foregroundStyle(DSColors.inkMute)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .font(DSTypography.mono(s(9)))
                    .tracking(0.8)
                    .accessibilityElement(children: .combine)
                }
            }
            // ToolLogRow が開いたときの中身と同じインデント量。
            .padding(.leading, 16)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "ユーザー" : "アシスタント")
    }

    /// `● HH:mm:ss  ROLE` — ToolLogRow のヘッダー行と同じ字送り・同じドット径にする。
    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // ToolLogRow は先頭に開閉用の chevron（幅 8）を持つ。発言には開閉が無いので
            // 同じ幅の空白を置き、ドットの位置を縦に揃える。
            Color.clear.frame(width: 8, height: 1)

            Circle()
                .fill(roleColor)
                .frame(width: 6, height: 6)

            if let timestamp = entry.timestamp {
                Text(Self.timeFormatter.string(from: timestamp))
                    .foregroundStyle(DSColors.inkMute)
            }

            if !isUser, let agentType {
                // エージェントの発言はロゴを添える（自分の発言との差が一目で付く）。
                AgentMark(agentType: agentType, size: s(9), alignedWithFontSize: s(9))
            }

            Text(roleLabel)
                .foregroundStyle(roleColor.opacity(isUser ? 1 : 0.9))

            Spacer(minLength: 0)
        }
        .font(DSTypography.mono(s(9), weight: .semibold))
        .tracking(1.0)
    }
}

@MainActor
enum AgentNotchMarkdownTheme {
    static func theme(scale: CGFloat = 1.0) -> MarkdownUI.Theme {
        let bodySize = (11 * scale * 2).rounded() / 2
        let codeSize = (9 * scale * 2).rounded() / 2
        return Theme.gitHub
            .text {
                ForegroundColor(DSColors.ink.opacity(0.85))
                BackgroundColor(nil)
                FontSize(bodySize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(codeSize)
                ForegroundColor(DSColors.ink)
                BackgroundColor(DSColors.surfaceStrong)
            }
            .codeBlock { configuration in
                // ツールログの出力ブロックと同じ「黒地 + 細い枠」に揃える。
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(codeSize)
                        ForegroundColor(DSColors.ink.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSColors.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DSColors.lineFaint, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
    }
}

#Preview("Chat Message") {
    VStack(alignment: .leading, spacing: 4) {
        ChatMessageView(
            entry: ChatEntry(
                role: .user,
                textContent: "サーバーの起動スクリプトを直して",
                timestamp: .now
            ),
            agentType: .claudeCode
        )
        ChatMessageView(
            entry: ChatEntry(
                role: .assistant,
                textContent: "`scripts/start.sh` の権限を修正しました。",
                toolUses: [.init(name: "Bash", inputSummary: "chmod +x scripts/start.sh")],
                timestamp: .now
            ),
            agentType: .claudeCode
        )
    }
    .padding(16)
    .frame(width: 420)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
