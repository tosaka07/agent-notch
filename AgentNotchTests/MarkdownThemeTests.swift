import AppKit
import SwiftUI
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

private actor RecordingCodeHighlighter: CodeHighlighting {
    private var requests: [CodeHighlightRequest] = []

    func highlight(_ request: CodeHighlightRequest) async -> HighlightedCode {
        requests.append(request)
        return HighlightedCode(lines: PlainTextCodeHighlighter.plainLines(request.source))
    }

    func firstRequest() -> CodeHighlightRequest? {
        requests.first
    }
}

@Suite("Markdown theme")
@MainActor
struct MarkdownThemeTests {
    @Test("A fenced code block uses the shared asynchronous highlighting interface")
    func fencedCodeBlockUsesSharedHighlighter() async throws {
        let highlighter = RecordingCodeHighlighter()
        let view = ChatMessageView(
            entry: ChatEntry(
                role: .assistant,
                textContent: """
                    ```swift
                    let value = 1
                    ```
                    """,
                timestamp: .now
            ),
            agentType: nil
        )
        .codeHighlighter(highlighter)
        .frame(width: 320, height: 120, alignment: .topLeading)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        hostingView.layoutSubtreeIfNeeded()

        for _ in 0..<20 {
            if await highlighter.firstRequest() != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await highlighter.firstRequest()
        let request = try #require(captured)
        #expect(request.source == "let value = 1")
        #expect(request.languageHint == .language("swift"))
    }

    @Test("Heading and thematic-break borders are white on the dark timeline")
    func structuralBordersAreWhite() throws {
        let view = ChatMessageView(
            entry: ChatEntry(
                role: .assistant,
                textContent: "# Headline\n\n## Subheadline\n\n---",
                timestamp: .now
            ),
            agentType: nil
        )
        .frame(width: 320, height: 260, alignment: .topLeading)
        .padding(20)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let contentRange =
            Int(CGFloat(30) * bitmapScale(bitmap))..<Int(CGFloat(340) * bitmapScale(bitmap))
        let lineRows = (0..<bitmap.pixelsHigh).filter { y in
            let brightPixels = contentRange.count { x in
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB)
                else { return false }
                return color.alphaComponent > 0.5
                    && color.redComponent > 0.9
                    && color.greenComponent > 0.9
                    && color.blueComponent > 0.9
            }
            return brightPixels > contentRange.count * 3 / 4
        }

        #expect(
            contiguousGroups(in: lineRows).count == 3,
            "Expected white H1, H2, and thematic-break borders, got line rows \(lineRows)"
        )
    }

    private func bitmapScale(_ bitmap: NSBitmapImageRep) -> CGFloat {
        CGFloat(bitmap.pixelsWide) / bitmap.size.width
    }

    private func contiguousGroups(in values: [Int]) -> [[Int]] {
        values.reduce(into: [[Int]]()) { groups, value in
            if let last = groups.last?.last, value == last + 1 {
                groups[groups.count - 1].append(value)
            } else {
                groups.append([value])
            }
        }
    }
}
