import Foundation

/// A structured diff attached to a tool execution.
///
/// Keeping file boundaries and context here lets renderers choose their own
/// highlighting strategy without having to parse the original transcript again.
public struct ToolDiff: Sendable, Hashable {
    public let files: [ToolDiffFile]

    public init(files: [ToolDiffFile]) {
        self.files = files
    }

    public var removedLines: [String] {
        files.flatMap { file in
            file.lines.compactMap { $0.kind == .removed ? $0.text : nil }
        }
    }

    public var addedLines: [String] {
        files.flatMap { file in
            file.lines.compactMap { $0.kind == .added ? $0.text : nil }
        }
    }
}

/// One file in a structured tool diff.
public struct ToolDiffFile: Sendable, Hashable {
    /// Full path when the transcript provides one.
    public let path: String?
    public let lines: [ToolDiffLine]

    public init(path: String?, lines: [ToolDiffLine]) {
        self.path = path
        self.lines = lines
    }
}

/// A source line in a tool diff, in transcript order.
public struct ToolDiffLine: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case context
        case removed
        case added
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Log of a single tool execution: the transcript's `tool_use` and `tool_result` joined by
/// `tool_use_id` into one record.
///
/// Used by the LOG tab of the session detail to show what ran and what came back. Chat entries
/// (`ChatEntry`) carry only the tool name and an input summary, so the result body is picked up here.
public struct ToolLogEntry: Identifiable, Sendable {
    /// How to render the output. Derived from the tool name.
    public enum Kind: Sendable {
        /// Shell command: `$ command` followed by its output.
        case command
        /// Search results; lines rendered as a table.
        case table
        /// A diff; `-` and `+` lines are colored.
        case diff
        /// Anything else; plain monospaced text.
        case text
    }

    public let id: String
    /// Tool name (`Bash`, `Grep`, `Edit`, ...).
    public let name: String
    public let timestamp: Date?
    /// Summary of the input (command / path / pattern).
    public let inputSummary: String
    /// The shell command itself (`Bash` only).
    public let command: String?
    /// Structured diff (`Edit` / `Write` / `apply_patch` only).
    public let diff: ToolDiff?
    /// Compatibility projections used by summaries and older callers.
    public var removedLines: [String] { diff?.removedLines ?? [] }
    public var addedLines: [String] { diff?.addedLines ?? [] }
    /// The tool output body, or nil when unavailable (e.g. still running).
    public let output: String?
    public let isError: Bool
    public let kind: Kind

    public init(
        id: String,
        name: String,
        timestamp: Date?,
        inputSummary: String,
        command: String? = nil,
        diff: ToolDiff? = nil,
        removedLines: [String] = [],
        addedLines: [String] = [],
        output: String?,
        isError: Bool,
        kind: Kind
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.inputSummary = inputSummary
        self.command = command
        if let diff {
            self.diff = diff
        } else if !removedLines.isEmpty || !addedLines.isEmpty {
            self.diff = ToolDiff(files: [
                ToolDiffFile(
                    path: nil,
                    lines:
                        removedLines.map { ToolDiffLine(kind: .removed, text: $0) }
                        + addedLines.map { ToolDiffLine(kind: .added, text: $0) }
                )
            ])
        } else {
            self.diff = nil
        }
        self.output = output
        self.isError = isError
        self.kind = kind
    }

    /// Result summary shown in the header. The transcript carries no exit status such as `exit 0`,
    /// so this is built from what is available: error flag, line count, and diff sizes.
    public var resultSummary: String {
        if isError { return AppLocalization.localized("error") }
        switch kind {
        case .diff:
            var parts: [String] = []
            if !addedLines.isEmpty { parts.append("+\(addedLines.count)") }
            if !removedLines.isEmpty { parts.append("−\(removedLines.count)") }
            return parts.joined(separator: " ")
        case .table, .command, .text:
            guard let output, !output.isEmpty else { return "" }
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false).count
            return lines <= 1
                ? AppLocalization.localized("1 line")
                : AppLocalization.localized("\(lines) lines")
        }
    }

    /// Picks the rendering style from the tool name. Accepts both Claude's and Codex's
    /// vocabularies (exec_command, apply_patch, ...).
    public static func kind(forToolNamed name: String) -> Kind {
        switch name {
        case "Bash", "BashOutput", "KillShell", "exec", "exec_command", "shell", "local_shell": .command
        case "Grep", "Glob", "TodoWrite": .table
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": .diff
        default: .text
        }
    }
}

/// One entry in a session's timeline; the type that lets chat messages and tool runs be
/// interleaved in chronological order.
///
/// Splitting CHAT and LOG into tabs would break the ordering between what was said and what ran,
/// so — like Claude Code itself — everything goes into a single timeline with tools collapsed by default.
public enum TranscriptEntry: Identifiable, Sendable {
    case message(ChatEntry)
    case tool(ToolLogEntry)

    public var id: String {
        switch self {
        case .message(let entry): "msg-" + entry.id
        case .tool(let entry): "tool-" + entry.id
        }
    }

    public var timestamp: Date? {
        switch self {
        case .message(let entry): entry.timestamp
        case .tool(let entry): entry.timestamp
        }
    }
}

/// A single row as actually drawn in the timeline.
///
/// `TranscriptEntry` is the parse result — the transcript in its original order. This type is the
/// display-oriented shape derived from it: consecutive runs of the same tool collapse into one row,
/// because five back-to-back Reads taking five rows would push the surrounding conversation off
/// screen and make the flow unreadable.
///
/// Kept as a separate enum so parse results and display concerns don't share a type
/// (`TranscriptReader`'s tests want to assert the uncollapsed order).
public enum TimelineRow: Identifiable, Sendable {
    case message(ChatEntry)
    /// A run of consecutive same-named tool executions. A single execution also goes here (`entries` is never empty).
    case toolRun([ToolLogEntry])

    public var id: String {
        switch self {
        case .message(let entry): "msg-" + entry.id
        // Use the first entry's id as the representative: as long as the first entry is unchanged,
        // a resized run still counts as the same row and the scroll position does not jump.
        case .toolRun(let entries): "tool-" + (entries.first?.id ?? "")
        }
    }

    /// Collapses consecutive same-named tools into one row. Messages are never collapsed.
    public static func rows(from entries: [TranscriptEntry]) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        var run: [ToolLogEntry] = []

        func flushRun() {
            guard !run.isEmpty else { return }
            rows.append(.toolRun(run))
            run = []
        }

        for entry in entries {
            switch entry {
            case .message(let message):
                flushRun()
                rows.append(.message(message))
            case .tool(let tool):
                // Break the run when the tool name changes (BASH BASH READ READ becomes 2 rows).
                if let last = run.last, last.name != tool.name { flushRun() }
                run.append(tool)
            }
        }
        flushRun()
        return rows
    }
}
