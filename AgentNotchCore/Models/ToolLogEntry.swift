import Foundation

/// ツール実行 1 件のログ。transcript の `tool_use` と `tool_result` を
/// `tool_use_id` で対応付けて 1 件にまとめたもの。
///
/// セッション詳細の LOG タブが「何を実行して何が返ったか」を出すために使う。
/// チャット（`ChatEntry`）はツール名と入力要約しか持たないので、こちらで結果本文まで拾う。
public struct ToolLogEntry: Identifiable, Sendable {
    /// 出力の見せ方。ツール名から決める。
    public enum Kind: Sendable {
        /// シェルコマンド。`$ command` + 出力。
        case command
        /// 検索結果。行を表として見せる。
        case table
        /// 差分。`-` / `+` 行に色を付ける。
        case diff
        /// それ以外。素の等幅テキスト。
        case text
    }

    public let id: String
    /// ツール名（`Bash` / `Grep` / `Edit` 等）。
    public let name: String
    public let timestamp: Date?
    /// 入力の要約（コマンド / パス / パターン）。
    public let inputSummary: String
    /// シェルコマンド本文（`Bash` のみ）。
    public let command: String?
    /// 差分の行（`Edit` / `Write` のみ）。`removed` が先、`added` が後。
    public let removedLines: [String]
    public let addedLines: [String]
    /// ツールの出力本文。取れなければ nil（実行中など）。
    public let output: String?
    public let isError: Bool
    public let kind: Kind

    public init(
        id: String,
        name: String,
        timestamp: Date?,
        inputSummary: String,
        command: String? = nil,
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
        self.removedLines = removedLines
        self.addedLines = addedLines
        self.output = output
        self.isError = isError
        self.kind = kind
    }

    /// 見出しに出す結果の要約。`exit 0` のような終了状態は transcript に無いので、
    /// 取れる情報（エラー有無・行数・差分の増減）から組み立てる。
    public var resultSummary: String {
        if isError { return "error" }
        switch kind {
        case .diff:
            var parts: [String] = []
            if !addedLines.isEmpty { parts.append("+\(addedLines.count)") }
            if !removedLines.isEmpty { parts.append("−\(removedLines.count)") }
            return parts.joined(separator: " ")
        case .table, .command, .text:
            guard let output, !output.isEmpty else { return "" }
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false).count
            return lines <= 1 ? "1 line" : "\(lines) lines"
        }
    }

    /// ツール名から出力の見せ方を決める。
    public static func kind(forToolNamed name: String) -> Kind {
        switch name {
        case "Bash", "BashOutput", "KillShell": .command
        case "Grep", "Glob", "TodoWrite": .table
        case "Edit", "Write", "MultiEdit", "NotebookEdit": .diff
        default: .text
        }
    }
}

/// セッションのタイムライン 1 件。チャットのメッセージとツール実行を**時系列で混ぜる**ための型。
///
/// タブで CHAT / LOG を分けると会話とツールの前後関係が切れてしまうので、
/// Claude Code 本体と同じく 1 本のタイムラインに混ぜ、ツールは既定で畳んでおく。
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
