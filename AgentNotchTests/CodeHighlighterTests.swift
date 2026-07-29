import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Diff Code Highlighting Tests")
struct CodeHighlighterTests {
    @Test("Language resolution accepts paths and explicit Markdown fence languages")
    func resolvesLanguageHints() {
        #expect(CodeLanguageResolver.language(for: .filePath("/tmp/App.swift")) == "swift")
        #expect(CodeLanguageResolver.language(for: .filePath("web/component.tsx")) == "typescript")
        #expect(CodeLanguageResolver.language(for: .filePath("Dockerfile")) == "dockerfile")
        #expect(CodeLanguageResolver.language(for: .filePath("notes.unknown")) == nil)
        #expect(CodeLanguageResolver.language(for: .language("js")) == "javascript")
        #expect(CodeLanguageResolver.language(for: .language("swift linenums")) == "swift")
        #expect(CodeLanguageResolver.language(for: .language("plaintext")) == nil)
        #expect(CodeLanguageResolver.language(for: nil) == nil)
    }

    @Test("Plain adapter preserves empty and trailing lines")
    func plainAdapterPreservesLineAlignment() async {
        let result = await PlainTextCodeHighlighter().highlight(
            CodeHighlightRequest(source: "let x = 1\n\n", languageHint: .language("swift"))
        )
        #expect(result.lines.map { String($0.characters) } == ["let x = 1", "", ""])
        #expect(String(result.attributedString.characters) == "let x = 1\n\n")
    }

    @Test("Diff plan reconstructs both source snapshots and maps changed lines")
    func buildsOldAndNewSnapshots() {
        let file = ToolDiffFile(
            path: "App.swift",
            lines: [
                ToolDiffLine(kind: .context, text: "struct App {"),
                ToolDiffLine(kind: .removed, text: "let value = 1"),
                ToolDiffLine(kind: .added, text: "let value = 2"),
                ToolDiffLine(kind: .context, text: "}"),
            ]
        )

        let plan = DiffHighlightPlan(file: file)
        #expect(plan.oldSource == "struct App {\nlet value = 1\n}")
        #expect(plan.newSource == "struct App {\nlet value = 2\n}")
        #expect(plan.oldLineIndexByDiffLine[1] == 1)
        #expect(plan.newLineIndexByDiffLine[2] == 1)
        #expect(plan.oldLineIndexByDiffLine[2] == nil)
        #expect(plan.newLineIndexByDiffLine[1] == nil)
    }

    @Test("Production adapter returns line-aligned source")
    func productionAdapterPreservesLineAlignment() async {
        let result = await HighlighterSwiftCodeHighlighter().highlight(
            CodeHighlightRequest(
                source: "struct App {\n    let value = 1\n}",
                languageHint: .language("swift")
            )
        )

        #expect(
            result.lines.map { String($0.characters) } == [
                "struct App {", "    let value = 1", "}",
            ])
        #expect(result.lines[0].runs.count > 1)
    }
}
