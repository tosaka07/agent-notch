import AgentNotchCore
import AppKit
import Foundation
@preconcurrency import Highlighter
import SwiftUI

/// Where a caller got its language information.
enum CodeLanguageHint: Sendable, Hashable {
    /// Infer the language from a diff's target path.
    case filePath(String)
    /// Use a fenced Markdown code block's explicit language.
    case language(String)
}

/// The complete input needed by a code-highlighting adapter.
struct CodeHighlightRequest: Sendable, Hashable {
    let source: String
    let languageHint: CodeLanguageHint?
}

/// Line-aligned highlighted code. Adapters must return exactly one item for
/// every newline-separated source line.
struct HighlightedCode: Sendable {
    let lines: [AttributedString]

    /// Reassembles a whole code block while preserving every line's attributes.
    var attributedString: AttributedString {
        lines.enumerated().reduce(into: AttributedString()) { result, item in
            if item.offset > 0 {
                result.append(AttributedString("\n"))
            }
            result.append(item.element)
        }
    }
}

/// Builds the old and new source snapshots used for highlighting while keeping
/// a mapping back to each line in the displayed diff.
struct DiffHighlightPlan: Sendable, Equatable {
    let oldSource: String
    let newSource: String
    let oldLineIndexByDiffLine: [Int: Int]
    let newLineIndexByDiffLine: [Int: Int]

    init(file: ToolDiffFile) {
        var oldLines: [String] = []
        var newLines: [String] = []
        var oldIndices: [Int: Int] = [:]
        var newIndices: [Int: Int] = [:]

        for (diffIndex, line) in file.lines.enumerated() {
            switch line.kind {
            case .context:
                oldIndices[diffIndex] = oldLines.count
                newIndices[diffIndex] = newLines.count
                oldLines.append(line.text)
                newLines.append(line.text)
            case .removed:
                oldIndices[diffIndex] = oldLines.count
                oldLines.append(line.text)
            case .added:
                newIndices[diffIndex] = newLines.count
                newLines.append(line.text)
            }
        }

        oldSource = oldLines.joined(separator: "\n")
        newSource = newLines.joined(separator: "\n")
        oldLineIndexByDiffLine = oldIndices
        newLineIndexByDiffLine = newIndices
    }
}

/// The seam between the diff UI and a concrete syntax-highlighting engine.
protocol CodeHighlighting: Sendable {
    func highlight(_ request: CodeHighlightRequest) async -> HighlightedCode
}

/// A deterministic fallback and test adapter.
struct PlainTextCodeHighlighter: CodeHighlighting {
    func highlight(_ request: CodeHighlightRequest) async -> HighlightedCode {
        HighlightedCode(lines: Self.plainLines(request.source))
    }

    static func plainLines(_ source: String) -> [AttributedString] {
        source.components(separatedBy: "\n").map(AttributedString.init)
    }
}

/// Production adapter backed by HighlighterSwift/highlight.js.
///
/// The actor serializes access to JavaScriptCore and keeps that implementation
/// detail out of SwiftUI. Replacing this with Tree-sitter only requires another
/// `CodeHighlighting` conformer.
actor HighlighterSwiftCodeHighlighter: CodeHighlighting {
    static let shared = HighlighterSwiftCodeHighlighter()

    private var engine: Highlighter?
    private var cache: [CodeHighlightRequest: HighlightedCode] = [:]
    private static let maxCacheEntries = 128

    func highlight(_ request: CodeHighlightRequest) async -> HighlightedCode {
        if let cached = cache[request] { return cached }

        let fallback = HighlightedCode(lines: PlainTextCodeHighlighter.plainLines(request.source))
        guard !Task.isCancelled,
            let language = CodeLanguageResolver.language(for: request.languageHint)
        else {
            return fallback
        }

        let highlighter: Highlighter
        if let engine {
            highlighter = engine
        } else {
            guard let newEngine = Highlighter() else { return fallback }
            newEngine.ignoreIllegals = true
            newEngine.setTheme("github-dark")
            engine = newEngine
            highlighter = newEngine
        }

        guard let rendered = highlighter.highlight(request.source, as: language),
            rendered.string == request.source,
            !Task.isCancelled
        else {
            return fallback
        }

        let result = HighlightedCode(lines: Self.lines(from: rendered, source: request.source))
        if cache.count >= Self.maxCacheEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[request] = result
        return result
    }

    /// Removes layout attributes owned by the UI while retaining token colors.
    private static func lines(
        from rendered: NSAttributedString,
        source: String
    ) -> [AttributedString] {
        let mutable = NSMutableAttributedString(attributedString: rendered)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.font, range: fullRange)
        mutable.removeAttribute(.backgroundColor, range: fullRange)
        mutable.removeAttribute(.paragraphStyle, range: fullRange)

        let sourceLines = source.components(separatedBy: "\n")
        var location = 0
        return sourceLines.map { line in
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            location += length + 1
            return AttributedString(mutable.attributedSubstring(from: range))
        }
    }
}

/// Converts caller-specific hints into highlight.js language identifiers.
///
/// Unknown file extensions stay plain. Explicit Markdown fence languages are
/// passed through after normalizing common aliases, because the fence is an
/// author-provided declaration rather than fragment auto-detection.
enum CodeLanguageResolver {
    static func language(for hint: CodeLanguageHint?) -> String? {
        switch hint {
        case .filePath(let path):
            return language(forFilePath: path)
        case .language(let fence):
            return language(forMarkdownFence: fence)
        case nil:
            return nil
        }
    }

    private static func language(forFilePath filePath: String) -> String? {
        guard !filePath.isEmpty else { return nil }
        let fileName = (filePath as NSString).lastPathComponent.lowercased()

        switch fileName {
        case "dockerfile": return "dockerfile"
        case "makefile", "gnumakefile": return "makefile"
        case "gemfile", "rakefile": return "ruby"
        default: break
        }

        switch (fileName as NSString).pathExtension {
        case "swift": return "swift"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "ts", "tsx", "mts", "cts": return "typescript"
        case "py", "pyw": return "python"
        case "rb": return "ruby"
        case "rs": return "rust"
        case "go": return "go"
        case "kt", "kts": return "kotlin"
        case "java": return "java"
        case "c", "h": return "c"
        case "cc", "cpp", "cxx", "hpp", "hh": return "cpp"
        case "cs": return "csharp"
        case "m", "mm": return "objectivec"
        case "sh", "bash", "zsh": return "bash"
        case "json", "jsonc": return "json"
        case "yaml", "yml": return "yaml"
        case "xml", "html", "htm", "svg", "vue": return "xml"
        case "md", "markdown": return "markdown"
        case "css": return "css"
        case "scss": return "scss"
        case "less": return "less"
        case "sql": return "sql"
        case "toml", "ini", "cfg": return "ini"
        default: return nil
        }
    }

    private static func language(forMarkdownFence fence: String) -> String? {
        guard
            let language = fence.split(whereSeparator: \.isWhitespace).first?
                .lowercased(),
            !language.isEmpty
        else {
            return nil
        }

        switch language {
        case "text", "txt", "plaintext", "plain", "none": return nil
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "sh", "shell", "zsh", "console": return "bash"
        case "c++": return "cpp"
        case "c#": return "csharp"
        case "objc", "objective-c": return "objectivec"
        default: return language
        }
    }
}

extension EnvironmentValues {
    @Entry var codeHighlighter: any CodeHighlighting = HighlighterSwiftCodeHighlighter.shared
}

extension View {
    /// Overrides syntax highlighting for a subtree (for previews, tests, or a
    /// future Tree-sitter implementation).
    func codeHighlighter(_ highlighter: any CodeHighlighting) -> some View {
        environment(\.codeHighlighter, highlighter)
    }
}
