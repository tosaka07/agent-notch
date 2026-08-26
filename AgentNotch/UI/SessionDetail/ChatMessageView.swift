import AgentNotchCore
import Defaults
import MarkdownUI
import SwiftUI

/// A single message in the timeline.
///
/// # Shape
/// One line, with the body starting immediately after the marker. It rides the
/// same columns as `ToolLogRow` (`TimelineMetrics`), so messages and tool calls
/// interleave and still read as one timeline.
///
/// ```
///                    ┌─────────────────────────────┐
///                    │ Fix the server start script │
///                    └─────────────────────────────┘
/// ✳  Fixed the permissions on `scripts/start.sh`.
/// ›  BASH  chmod +x scripts/start.sh
/// ```
///
/// # The speaker is conveyed by position and mark
/// There are no name labels (YOU / CLAUDE CODE). The agent's name is already in
/// the detail view's header, so repeating it is redundant, and spending a line
/// per message on a name pushes the body downward.
///
/// **Your messages are right-aligned bubbles; the agent's are left-aligned with
/// a logo.** It reads the way a chat app does, so whose turn it is comes across
/// from the shape alone, without color or labels.
struct ChatMessageView: View {
    let entry: ChatEntry
    /// Which logo accompanies the agent's messages. No logo when nil.
    var agentType: AgentType?

    @Default(.textSize) private var textSize
    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var isUser: Bool { entry.role == .user }

    /// Space always kept to the left of your own messages.
    ///
    /// It never shrinks below this, so even a long message stops short of the
    /// left edge and still reads as a bubble on the right. Short messages
    /// collapse to their content's width, with the `Spacer` taking the rest.
    private static let userLeadingInset: CGFloat = 96

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TimelineMetrics.spacing) {
            if isUser {
                // Your messages go right. The large gap that opens on the left
                // makes "this is my turn" legible from shape alone when
                // skimming the timeline.
                Spacer(minLength: Self.userLeadingInset)
                messageBody
            } else {
                marker
                messageBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Messages get generous vertical space. Tool rows naturally run
        // together in a tight sequence, but a message marks where the subject
        // changes — without breathing room it would look like part of the tool
        // log.
        .padding(.vertical, DSSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isUser
                ? L("Message from you")
                : L("Message from \(agentType?.displayName ?? L("the agent"))"))
    }

    /// The mark saying whose message this is, centered in the same column as a
    /// tool row's chevron.
    ///
    /// **Your own messages get no mark.** The bubble surface already says "you
    /// wrote this", so a dot would say it a second time. The column keeps its
    /// width regardless, so the body's left edge lines up with the other rows.
    @ViewBuilder
    private var marker: some View {
        Group {
            if !isUser, let agentType {
                AgentMark(agentType: agentType, size: s(10), alignedWithFontSize: s(10))
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .frame(width: TimelineMetrics.marker)
    }

    /// The message body.
    ///
    /// **Only your own messages get a surface.** The agent's output dominates
    /// the timeline, so left as plain text, what you actually asked for gets
    /// buried in the flow. The marker column is empty here, so the surface does
    /// all the talking.
    @ViewBuilder
    private var messageBody: some View {
        if isUser {
            messageContent
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                // Your messages float in front of the flow, one step brighter
                // than a surface that is only there to be read.
                .background(DSSurfaceFill(.raised))
                .clipShape(DSShape.rounded(DSShape.inset))
                .overlay(
                    DSShape.rounded(DSShape.inset)
                        .stroke(DSColors.lineFaint, lineWidth: 1)
                )
        } else {
            messageContent
        }
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !entry.textContent.isEmpty {
                Markdown(entry.textContent)
                    .markdownTheme(AgentNotchMarkdownTheme.theme(scale: scale))
                    .textSelection(.enabled)
            }

            ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                // Styled like a tool-call row (ToolLogRow) so a tool_use picked
                // up from the transcript reads as the same kind of thing.
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
    }

}

/// Plain-first, asynchronously highlighted contents of a fenced Markdown block.
///
/// MarkdownUI's `CodeSyntaxHighlighter` interface is synchronous, so using it
/// would move JavaScriptCore work back onto view rendering. This view crosses
/// the same asynchronous `CodeHighlighting` seam as the diff renderer instead.
private struct AgentNotchMarkdownCodeBlock: View {
    let content: String
    let language: String?
    let fontSize: CGFloat

    @Environment(\.codeHighlighter) private var highlighter
    @State private var rendered: RenderedCode?

    private struct RenderedCode {
        let request: CodeHighlightRequest
        let code: AttributedString
    }

    private var request: CodeHighlightRequest {
        CodeHighlightRequest(
            source: content,
            languageHint: language.map(CodeLanguageHint.language)
        )
    }

    private var displayedCode: AttributedString {
        guard let rendered, rendered.request == request else {
            return AttributedString(content)
        }
        return rendered.code
    }

    var body: some View {
        Text(displayedCode)
            .font(DSTypography.mono(fontSize))
            .foregroundStyle(DSColors.ink.opacity(0.8))
            .task(id: request) {
                let result = await highlighter.highlight(request)
                guard !Task.isCancelled else { return }
                rendered = RenderedCode(request: request, code: result.attributedString)
            }
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
            // GitHub's heading rules use dark gray dividers even in dark mode.
            // On the notch's black timeline those rules nearly disappear, so
            // retain GitHub's type scale and spacing but use the app's white ink
            // for the structural line.
            .heading1 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .relativePadding(.bottom, length: .em(0.3))
                        .relativeLineSpacing(.em(0.125))
                        .markdownMargin(top: 24, bottom: 16)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(2))
                        }
                    Divider().overlay(DSColors.ink)
                }
            }
            .heading2 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .relativePadding(.bottom, length: .em(0.3))
                        .relativeLineSpacing(.em(0.125))
                        .markdownMargin(top: 24, bottom: 16)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(1.5))
                        }
                    Divider().overlay(DSColors.ink)
                }
            }
            .codeBlock { configuration in
                AgentNotchMarkdownCodeBlock(
                    content: configuration.content,
                    language: configuration.language,
                    fontSize: codeSize
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSSurfaceFill(.inset))
                .overlay(
                    DSShape.rounded(DSShape.inset)
                        .stroke(DSColors.lineFaint, lineWidth: 0.5)
                )
                .clipShape(DSShape.rounded(DSShape.inset))
                // Overriding `.codeBlock` also drops the bottom margin the
                // base theme carried. Paragraphs and lists use 16, so code
                // blocks match it here rather than sticking to whatever
                // follows them.
                .markdownMargin(top: 0, bottom: 16)
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    // Columns align through spacing and typography; vertical
                    // rules only add noise. Keep faint row separators so wide
                    // rows remain easy to track.
                    .markdownTableBorderStyle(
                        .init(
                            .insideHorizontalBorders,
                            color: DSColors.lineFaint,
                            width: 0.5
                        )
                    )
                    // The detail timeline already supplies its surface. A
                    // table should not introduce zebra stripes or another fill.
                    .markdownTableBackgroundStyle(.clear)
                    .markdownMargin(top: 0, bottom: 16)
            }
            .thematicBreak {
                Divider()
                    .relativeFrame(height: .em(0.25))
                    .overlay(DSColors.ink)
                    .markdownMargin(top: 24, bottom: 24)
            }
    }
}

#Preview("Chat Message") {
    VStack(alignment: .leading, spacing: 4) {
        ChatMessageView(
            entry: ChatEntry(
                role: .user,
                textContent: "Fix the server start script",
                timestamp: .now
            ),
            agentType: .claudeCode
        )
        ChatMessageView(
            entry: ChatEntry(
                role: .assistant,
                textContent: """
                    Fixed the permissions on `scripts/start.sh`.

                    | File | Result |
                    | --- | --- |
                    | start.sh | Updated |
                    | deploy.sh | Unchanged |
                    """,
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
