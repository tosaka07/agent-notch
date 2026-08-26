import Foundation

public enum TranscriptReader {
    /// The message sequence for the chat display.
    ///
    /// With `includeToolUses` false, `tool_use` blocks are ignored and only text is returned,
    /// because the timeline emits tools as separate entries.
    public static func read(path: String, tail: Int = 50, includeToolUses: Bool = true) -> [ChatEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var entries: [ChatEntry] = []

        for line in lines {
            guard !line.isEmpty,
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

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
            entries.append(
                ChatEntry(
                    id: id, role: role, textContent: textContent, toolUses: toolUses, timestamp: timestamp))
        }

        if entries.count > tail {
            return Array(entries.suffix(tail))
        }
        return entries
    }

    /// A timeline interleaving chat and tool executions in chronological order.
    ///
    /// Being able to read the ordering between conversation and tools matters, so everything goes
    /// into one stream rather than separate CHAT and LOG views; the UI collapses the tools.
    /// An assistant message's text and its `tool_use` blocks share a line, so **only the text
    /// becomes a message and each tool_use becomes its own tool entry**, which keeps the same
    /// content from appearing twice.
    public static func readTimeline(path: String, tail: Int = 60) -> [TranscriptEntry] {
        // The Codex integration switch decides whether Codex's own files may be opened at all.
        guard CodexAccess.allowsTranscript(at: path) else { return [] }
        // Codex rollout files use a different format, so route them to the dedicated reader.
        if CodexTranscriptReader.isRollout(path: path) {
            return CodexTranscriptReader.readTimeline(path: path, tail: tail)
        }
        let messages = read(path: path, tail: tail, includeToolUses: false)
        let tools = readToolLog(path: path, tail: tail)

        var entries: [TranscriptEntry] = messages.map { .message($0) } + tools.map { .tool($0) }
        // Lines without a timestamp (the older format) keep their original order, so the index is used as a tiebreaker for a stable sort.
        let indexed = entries.enumerated().map { (offset: $0.offset, entry: $0.element) }
        entries = indexed.sorted { lhs, rhs in
            let l = lhs.entry.timestamp ?? .distantPast
            let r = rhs.entry.timestamp ?? .distantPast
            if l != r { return l < r }
            return lhs.offset < rhs.offset
        }.map(\.entry)

        return entries.count > tail ? Array(entries.suffix(tail)) : entries
    }

    /// The log of tool executions.
    ///
    /// In a transcript, an assistant message's `tool_use` block and the following user message's
    /// `tool_result` block correspond via `tool_use_id`. The result arrives either as a string or
    /// as a `[{type: "text", text: ...}]` block array; both are accepted.
    ///
    /// Executions still running (no result yet) are returned with `output == nil`.
    public static func readToolLog(path: String, tail: Int = 40) -> [ToolLogEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return [] }

        // tool_use_id in encounter order; results arrive later and are filled in by reference.
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
                        filePath: input["file_path"] as? String,
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
            let diff: ToolDiff? =
                kind == .diff
                ? toolDiff(
                    filePath: use.filePath,
                    oldString: use.oldString,
                    newString: use.newString
                )
                : nil
            return ToolLogEntry(
                id: id,
                name: use.name,
                timestamp: use.timestamp,
                inputSummary: use.inputSummary,
                command: use.command,
                diff: diff,
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
        let filePath: String?
        let oldString: String?
        let newString: String?
    }

    /// `tool_result.content` arrives either as a string or as `[{type:"text", text:...}]`.
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

    private static func toolDiff(
        filePath: String?,
        oldString: String?,
        newString: String?
    ) -> ToolDiff? {
        let lines =
            splitLines(oldString).map { ToolDiffLine(kind: .removed, text: $0) }
            + splitLines(newString).map { ToolDiffLine(kind: .added, text: $0) }
        guard !lines.isEmpty else { return nil }
        return ToolDiff(files: [ToolDiffFile(path: filePath, lines: lines)])
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
