import Foundation

public enum TranscriptReader {
    /// チャット表示用のメッセージ列。
    ///
    /// `includeToolUses` が false のときは `tool_use` を無視してテキストだけを返す
    /// （タイムラインではツールを独立エントリとして別に出すため）。
    public static func read(path: String, tail: Int = 50, includeToolUses: Bool = true) -> [ChatEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var entries: [ChatEntry] = []

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""
            guard type == "user" || type == "assistant" else { continue }
            guard let message = json["message"] as? [String: Any] else { continue }

            let timestamp = (json["timestamp"] as? String).flatMap { iso8601Date($0) }
            let role: ChatEntry.Role = type == "user" ? .user : .assistant

            var textContent = ""
            var toolUses: [ChatEntry.ToolUseEntry] = []

            if let contentStr = message["content"] as? String {
                textContent = contentStr
            } else if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        if !textContent.isEmpty { textContent += "\n" }
                        textContent += text
                    } else if blockType == "tool_use", includeToolUses {
                        let name = block["name"] as? String ?? "unknown"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let summary = summarizeToolInput(name: name, input: input)
                        toolUses.append(ChatEntry.ToolUseEntry(name: name, inputSummary: summary))
                    }
                }
            }

            guard !textContent.isEmpty || !toolUses.isEmpty else { continue }

            let id = json["uuid"] as? String ?? UUID().uuidString
            entries.append(ChatEntry(id: id, role: role, textContent: textContent, toolUses: toolUses, timestamp: timestamp))
        }

        if entries.count > tail {
            return Array(entries.suffix(tail))
        }
        return entries
    }

    /// チャットとツール実行を時系列に混ぜたタイムライン。
    ///
    /// 会話とツールの前後関係が読めることが重要なので、CHAT / LOG に分けず 1 本に混ぜる
    /// （UI 側でツールを畳んで出す）。assistant メッセージのテキストと `tool_use` は
    /// 同じ行に同居するため、**テキストだけを message として出し、tool_use は独立した
    /// tool エントリにする**（同じ内容が二重に出ないようにする）。
    public static func readTimeline(path: String, tail: Int = 60) -> [TranscriptEntry] {
        let messages = read(path: path, tail: tail, includeToolUses: false)
        let tools = readToolLog(path: path, tail: tail)

        var entries: [TranscriptEntry] = messages.map { .message($0) } + tools.map { .tool($0) }
        // timestamp が無い行（古い形式）は元の並びを保つため、安定ソートになるよう index を併用する。
        let indexed = entries.enumerated().map { (offset: $0.offset, entry: $0.element) }
        entries = indexed.sorted { lhs, rhs in
            let l = lhs.entry.timestamp ?? .distantPast
            let r = rhs.entry.timestamp ?? .distantPast
            if l != r { return l < r }
            return lhs.offset < rhs.offset
        }.map(\.entry)

        return entries.count > tail ? Array(entries.suffix(tail)) : entries
    }

    /// ツール実行のログ。
    ///
    /// transcript では assistant メッセージの `tool_use` ブロックと、続く user メッセージの
    /// `tool_result` ブロックが `tool_use_id` で対応する。結果は文字列か
    /// `[{type: "text", text: ...}]` のブロック配列で来るのでどちらも受ける。
    ///
    /// 実行中（結果が来ていない）ものは `output == nil` のまま返す。
    public static func readToolLog(path: String, tail: Int = 40) -> [ToolLogEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return [] }

        // tool_use_id → 並び順を保った index。結果が後から来るので参照で埋める。
        var order: [String] = []
        var uses: [String: PendingToolUse] = [:]
        var results: [String: (output: String, isError: Bool)] = [:]

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]]
            else { continue }

            let timestamp = (json["timestamp"] as? String).flatMap { iso8601Date($0) }

            for block in blocks {
                switch block["type"] as? String {
                case "tool_use":
                    guard let id = block["id"] as? String else { continue }
                    let name = block["name"] as? String ?? "unknown"
                    let input = block["input"] as? [String: Any] ?? [:]
                    uses[id] = PendingToolUse(
                        name: name,
                        timestamp: timestamp,
                        inputSummary: summarizeToolInput(name: name, input: input),
                        command: input["command"] as? String,
                        oldString: input["old_string"] as? String,
                        newString: input["new_string"] as? String ?? input["content"] as? String
                    )
                    order.append(id)
                case "tool_result":
                    guard let id = block["tool_use_id"] as? String else { continue }
                    results[id] = (
                        output: toolResultText(block["content"]),
                        isError: block["is_error"] as? Bool ?? false
                    )
                default:
                    continue
                }
            }
        }

        let recent = order.count > tail ? Array(order.suffix(tail)) : order
        return recent.compactMap { id in
            guard let use = uses[id] else { return nil }
            let result = results[id]
            let kind = ToolLogEntry.kind(forToolNamed: use.name)
            return ToolLogEntry(
                id: id,
                name: use.name,
                timestamp: use.timestamp,
                inputSummary: use.inputSummary,
                command: use.command,
                removedLines: kind == .diff ? splitLines(use.oldString) : [],
                addedLines: kind == .diff ? splitLines(use.newString) : [],
                output: result?.output,
                isError: result?.isError ?? false,
                kind: kind
            )
        }
    }

    private struct PendingToolUse {
        let name: String
        let timestamp: Date?
        let inputSummary: String
        let command: String?
        let oldString: String?
        let newString: String?
    }

    /// `tool_result.content` は文字列 or `[{type:"text", text:...}]` のどちらでも来る。
    private static func toolResultText(_ raw: Any?) -> String {
        if let text = raw as? String { return text }
        if let blocks = raw as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private static func splitLines(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.components(separatedBy: .newlines)
    }

    private static func summarizeToolInput(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            return cmd.count > 40 ? String(cmd.prefix(40)) + "..." : cmd
        case "Edit", "Write", "Read":
            let filePath = input["file_path"] as? String ?? ""
            return (filePath as NSString).lastPathComponent
        case "Grep", "Glob":
            return input["pattern"] as? String ?? ""
        default:
            return name
        }
    }

    private static func iso8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
