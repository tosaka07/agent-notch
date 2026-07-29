import Foundation

/// An unresolved `request_user_input` call recovered from a Codex rollout.
///
/// A rollout proves that the runtime is waiting, but it does not expose a
/// writable response channel. Callers therefore present these as
/// `QuestionResponseMode.terminalOnly` unless a live App Server request is
/// correlated separately.
public struct CodexRolloutQuestion: Sendable, Equatable {
    public let callId: String
    public let turnId: String?
    public let questions: [AskQuestionInfo.Question]
    public let autoResolutionMs: Int?
    public let receivedAt: Date

    public init(
        callId: String,
        turnId: String?,
        questions: [AskQuestionInfo.Question],
        autoResolutionMs: Int?,
        receivedAt: Date
    ) {
        self.callId = callId
        self.turnId = turnId
        self.questions = questions
        self.autoResolutionMs = autoResolutionMs
        self.receivedAt = receivedAt
    }

    public var expiresAt: Date {
        guard let autoResolutionMs else { return .distantFuture }
        return receivedAt.addingTimeInterval(TimeInterval(autoResolutionMs) / 1_000)
    }
}

/// Reads Codex CLI transcripts (rollout files).
///
/// The format differs from Claude's transcript (JSONL of `{"type":"user","message":{...}}`).
/// Rollouts live at `~/.codex/sessions/**/rollout-*.jsonl` and record
/// `{"timestamp":..., "type":"response_item"|"event_msg"|..., "payload":{...}}`.
/// Everything is normalized into `ChatEntry` / `ToolLogEntry` / `TranscriptEntry` / `TokenUsage`
/// so it can feed the existing UI unchanged. Callers are routed here by `isRollout` at the
/// entry points of `TranscriptReader` and `TranscriptParser`, so only format-specific code needs
/// to know this type exists.
///
/// # Lines that are read
/// - `response_item / message` — utterances, for the user and assistant roles only. Developer and
///   system messages are prompts Codex injects and are not shown.
/// - `response_item / function_call` plus `function_call_output` — tool executions, correlated by
///   **`call_id`**. (`id` is a different thing belonging to the response API and is not used.)
/// - `response_item / custom_tool_call` plus `custom_tool_call_output` — apply_patch and friends.
/// - `event_msg / token_count` — cumulative tokens (`info.total_token_usage`).
///
/// reasoning, turn_context, session_meta, and other event_msg lines are ignored.
public enum CodexTranscriptReader {
    // MARK: - Format detection

    /// Detects the rollout format from the vocabulary of the first line.
    ///
    /// The leading `session_meta` line embeds the entire base_instructions and can run to tens of
    /// kilobytes, so it is **matched as text within the first 4KB** rather than parsed as JSON.
    /// Every rollout line has a `payload` and a rollout-specific `type`; Claude's types
    /// (user, assistant, summary, ...) do not overlap.
    public static func isRollout(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { handle.closeFile() }
        let head = String(decoding: handle.readData(ofLength: 4096), as: UTF8.self)
        guard let firstLine = head.split(separator: "\n", omittingEmptySubsequences: true).first
        else { return false }
        let rolloutTypes = [
            "\"session_meta\"", "\"response_item\"", "\"event_msg\"", "\"turn_context\"", "\"compacted\"",
        ]
        return firstLine.contains("\"payload\"") && rolloutTypes.contains { firstLine.contains($0) }
    }

    /// Whether the rollout belongs to a Codex child agent rather than the root thread.
    ///
    /// Codex versions that do not expose parent/child identity on Stop hooks still persist
    /// it in the leading session_meta payload as `source.subagent`. The source field is near
    /// the start of the line, so this stays a fixed-size read even when base instructions make
    /// the full session_meta line very large.
    public static func isSubagentRollout(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { handle.closeFile() }
        let head = String(decoding: handle.readData(ofLength: 16 * 1024), as: UTF8.self)
        return head.range(
            of: #""source"\s*:\s*\{\s*"subagent"\s*:"#,
            options: .regularExpression
        ) != nil
    }

    // MARK: - Pending user input

    /// Reconstructs every request_user_input call that has no matching output.
    ///
    /// Rollouts are append-only and `function_call_output` uses the same
    /// `call_id`, so this also restores a question after Agent Notch restarts
    /// and removes it when the answer was entered directly in Codex.
    public static func pendingUserInputQuestions(path: String) -> [CodexRolloutQuestion] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return [] }
        return pendingUserInputQuestions(in: content.components(separatedBy: .newlines))
    }

    /// Pure line parser exposed for focused rollout fixtures.
    public static func pendingUserInputQuestions(in lines: [String]) -> [CodexRolloutQuestion] {
        var pending: [String: CodexRolloutQuestion] = [:]
        var order: [String] = []

        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["type"] as? String == "response_item",
                let payload = json["payload"] as? [String: Any]
            else { continue }

            switch payload["type"] as? String {
            case "function_call":
                guard payload["name"] as? String == "request_user_input",
                    let callId = payload["call_id"] as? String,
                    !callId.isEmpty
                else { continue }
                let arguments = parseArguments(payload["arguments"] as? String)
                guard let rawQuestions = arguments["questions"] as? [[String: Any]],
                    let parsedQuestions = CodexUserInputProtocol.parseQuestions(rawQuestions),
                    let autoResolutionMs = CodexUserInputProtocol.parseAutoResolutionMs(
                        arguments["autoResolutionMs"]
                    )
                else { continue }
                let turnId =
                    (payload["internal_chat_message_metadata_passthrough"] as? [String: Any])?[
                        "turn_id"
                    ] as? String
                let receivedAt =
                    (json["timestamp"] as? String).flatMap(iso8601Date)
                    ?? Date.distantPast
                let question = CodexRolloutQuestion(
                    callId: callId,
                    turnId: turnId,
                    questions: parsedQuestions.map(\.bannerQuestion),
                    autoResolutionMs: autoResolutionMs,
                    receivedAt: receivedAt
                )
                if pending[callId] == nil {
                    order.append(callId)
                }
                pending[callId] = question

            case "function_call_output":
                guard let callId = payload["call_id"] as? String else { continue }
                pending.removeValue(forKey: callId)

            default:
                continue
            }
        }

        return order.compactMap { pending[$0] }
    }

    // MARK: - Timeline

    /// A timeline interleaving utterances and tool executions.
    ///
    /// Rollouts are append-only, so line order is already chronological: unlike the Claude path,
    /// there is no timestamp sort and **the file's line order is preserved**.
    public static func readTimeline(path: String, tail: Int = 60) -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return [] }

        /// Slots in encounter order. Tool outputs arrive later and are filled in by reference.
        enum Slot {
            case message(ChatEntry)
            case tool(callId: String)
        }
        var slots: [Slot] = []
        var calls: [String: PendingCall] = [:]
        var outputs: [String: String] = [:]

        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            guard !line.isEmpty,
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                json["type"] as? String == "response_item",
                let payload = json["payload"] as? [String: Any]
            else { continue }

            let timestamp = (json["timestamp"] as? String).flatMap { iso8601Date($0) }

            switch payload["type"] as? String {
            case "message":
                guard let role = chatRole(payload["role"] as? String) else { continue }
                let text = messageText(payload, role: role)
                guard !text.isEmpty else { continue }
                // The id is the line number. Rollouts are append-only, so it stays stable across
                // reloads and the timeline's row identity (and scroll position) does not jump.
                slots.append(
                    .message(
                        ChatEntry(
                            id: "codex-\(index)", role: role, textContent: text,
                            toolUses: [], timestamp: timestamp
                        )))

            case "function_call":
                guard let callId = payload["call_id"] as? String else { continue }
                let name = payload["name"] as? String ?? "unknown"
                let args = parseArguments(payload["arguments"] as? String)
                let command = args["cmd"] as? String ?? args["command"] as? String
                calls[callId] = PendingCall(
                    name: name, timestamp: timestamp, command: command,
                    inputSummary: summarize(name: name, command: command, args: args),
                    patchText: nil
                )
                slots.append(.tool(callId: callId))

            case "custom_tool_call":
                guard let callId = payload["call_id"] as? String else { continue }
                let name = payload["name"] as? String ?? "unknown"
                let input = payload["input"] as? String
                let command = name == "exec" ? execCommands(in: input).joined(separator: " · ") : nil
                calls[callId] = PendingCall(
                    name: name, timestamp: timestamp, command: command,
                    inputSummary: name == "apply_patch"
                        ? patchedFileSummary(input)
                        : summarizeCustomToolInput(name: name, input: input, command: command),
                    patchText: name == "apply_patch" ? input : nil
                )
                slots.append(.tool(callId: callId))

            case "function_call_output", "custom_tool_call_output":
                guard let callId = payload["call_id"] as? String else { continue }
                outputs[callId] = toolOutputText(payload["output"])

            default:
                continue
            }
        }

        let entries: [TranscriptEntry] = slots.compactMap { slot in
            switch slot {
            case .message(let entry):
                return .message(entry)
            case .tool(let callId):
                guard let call = calls[callId] else { return nil }
                let output = outputs[callId]
                let kind = ToolLogEntry.kind(forToolNamed: call.name)
                let diff = kind == .diff ? parsePatch(call.patchText) : nil
                return .tool(
                    ToolLogEntry(
                        id: callId,
                        name: call.name,
                        timestamp: call.timestamp,
                        inputSummary: call.inputSummary,
                        command: call.command,
                        diff: diff,
                        output: output,
                        isError: output.map(looksLikeError) ?? false,
                        kind: kind
                    ))
            }
        }

        return entries.count > tail ? Array(entries.suffix(tail)) : entries
    }

    // MARK: - Tokens

    /// Cumulative tokens. `info.total_token_usage` on `event_msg / token_count` is already the
    /// running total at that point, so **only the last one** is read.
    ///
    /// Codex (OpenAI format) **includes** `cached_input_tokens` in `input_tokens`. To match
    /// Claude-style `TokenUsage`, where input excludes cache, the cached portion is subtracted
    /// from input when repacking.
    public static func parseCumulativeUsage(at path: String) -> TokenUsage {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return TokenUsage() }

        var latest: [String: Any]?
        for line in content.components(separatedBy: .newlines) {
            guard line.contains("\"token_count\""),
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let payload = json["payload"] as? [String: Any],
                payload["type"] as? String == "token_count",
                let info = payload["info"] as? [String: Any],
                let total = info["total_token_usage"] as? [String: Any]
            else { continue }
            latest = total
        }

        guard let latest else { return TokenUsage() }
        let input = latest["input_tokens"] as? Int ?? 0
        let cached = latest["cached_input_tokens"] as? Int ?? 0
        var usage = TokenUsage()
        usage.inputTokens = max(0, input - cached)
        usage.cacheReadTokens = cached
        usage.outputTokens = latest["output_tokens"] as? Int ?? 0
        return usage
    }

    // MARK: - Private

    private struct PendingCall {
        let name: String
        let timestamp: Date?
        let command: String?
        let inputSummary: String
        let patchText: String?
    }

    private static func chatRole(_ raw: String?) -> ChatEntry.Role? {
        switch raw {
        case "user": .user
        case "assistant": .assistant
        // developer and system are prompts Codex injects; they are not part of the conversation.
        default: nil
        }
    }

    /// Builds the text shown to the user from the content blocks.
    ///
    /// A user line mixes the person's own input with blocks Codex injects (AGENTS.md, environment
    /// information, permission explanations), so the injected ones are dropped **per block**.
    private static func messageText(_ payload: [String: Any], role: ChatEntry.Role) -> String {
        guard let blocks = payload["content"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for block in blocks {
            guard let type = block["type"] as? String,
                type == "input_text" || type == "output_text",
                let text = block["text"] as? String
            else { continue }
            if role == .user && isInjectedUserBlock(text) { continue }
            parts.append(text)
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Identifies blocks Codex injects into the user role, by their fixed leading markers.
    private static func isInjectedUserBlock(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = [
            "<environment_context>", "<permissions instructions>", "<user_instructions>",
            "<turn_aborted>", "# AGENTS.md instructions", "<INSTRUCTIONS>", "<system_",
        ]
        return markers.contains { trimmed.hasPrefix($0) }
    }

    /// `arguments` is a JSON string such as `{"cmd": "...", "workdir": ...}`.
    private static func parseArguments(_ raw: String?) -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    /// Tool results are either a plain string or response-style text blocks. Code-mode `exec`
    /// currently uses blocks such as `[{ "type": "input_text", "text": "..." }]`.
    private static func toolOutputText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        guard let blocks = value as? [[String: Any]] else { return "" }
        return blocks.compactMap { block in
            guard let type = block["type"] as? String,
                type == "input_text" || type == "output_text" || type == "text"
            else { return nil }
            return block["text"] as? String
        }
        .joined(separator: "\n")
    }

    private static func summarize(name: String, command: String?, args: [String: Any]) -> String {
        if let command, !command.isEmpty {
            return command.count > 40 ? String(command.prefix(40)) + "..." : command
        }
        if let query = args["query"] as? String { return query }
        return name
    }

    /// Summarizes the source body stored by custom tools.
    ///
    /// Newer Codex rollouts record the orchestration wrapper as `name: "exec"` and put its
    /// JavaScript source in `input`, rather than emitting `exec_command` as a function call.
    /// If no literal nested command can be extracted, keep a compact source preview instead of
    /// dropping the input and showing only the generic tool name.
    private static func summarizeCustomToolInput(
        name: String,
        input: String?,
        command: String?
    ) -> String {
        if let command, !command.isEmpty {
            return summarize(name: name, command: command, args: [:])
        }
        guard let input else { return name }
        let singleLine =
            input
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return name }
        return singleLine.count > 40 ? String(singleLine.prefix(40)) + "..." : singleLine
    }

    /// Extracts literal `cmd` / `command` values from calls such as:
    /// `tools.exec_command({"cmd":"swift test","workdir":"/tmp"})`.
    ///
    /// One `exec` body can orchestrate several commands. The object scanner tracks strings and
    /// escapes so braces inside shell commands do not terminate the JSON object prematurely.
    private static func execCommands(in source: String?) -> [String] {
        guard let source, !source.isEmpty else { return [] }
        let marker = "tools.exec_command"
        var commands: [String] = []
        var searchStart = source.startIndex

        while searchStart < source.endIndex,
            let markerRange = source.range(
                of: marker,
                range: searchStart..<source.endIndex
            )
        {
            var cursor = markerRange.upperBound
            skipWhitespace(in: source, cursor: &cursor)
            guard cursor < source.endIndex, source[cursor] == "(" else {
                searchStart = cursor
                continue
            }
            cursor = source.index(after: cursor)
            skipWhitespace(in: source, cursor: &cursor)
            guard cursor < source.endIndex, source[cursor] == "{",
                let objectEnd = jsonObjectEnd(in: source, from: cursor)
            else {
                searchStart = cursor
                continue
            }

            let object = String(source[cursor...objectEnd])
            if let data = object.data(using: .utf8),
                let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let command = args["cmd"] as? String ?? args["command"] as? String,
                !command.isEmpty
            {
                commands.append(command)
            }
            searchStart = source.index(after: objectEnd)
        }
        return commands
    }

    private static func skipWhitespace(in source: String, cursor: inout String.Index) {
        while cursor < source.endIndex, source[cursor].isWhitespace {
            cursor = source.index(after: cursor)
        }
    }

    /// Finds the closing brace of a JSON object embedded in JavaScript source.
    private static func jsonObjectEnd(
        in source: String,
        from start: String.Index
    ) -> String.Index? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var cursor = start

        while cursor < source.endIndex {
            let character = source[cursor]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                switch character {
                case "\"":
                    isInsideString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return cursor }
                default:
                    break
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    /// Summarizes apply_patch by the files it targets (`*** Add File: path` and similar).
    private static func patchedFileSummary(_ patch: String?) -> String {
        guard let patch else { return "apply_patch" }
        var files: [String] = []
        for line in patch.components(separatedBy: .newlines) {
            for marker in ["*** Add File: ", "*** Update File: ", "*** Delete File: "] {
                if line.hasPrefix(marker) {
                    files.append((String(line.dropFirst(marker.count)) as NSString).lastPathComponent)
                }
            }
        }
        return files.isEmpty ? "apply_patch" : files.joined(separator: ", ")
    }

    /// Parses an apply_patch body without discarding file boundaries, context, or line order.
    ///
    /// The patch format uses `*** Add/Update/Delete File:` headers rather than the
    /// `---`/`+++` headers of a unified diff.
    private static func parsePatch(_ patch: String?) -> ToolDiff? {
        guard let patch else { return nil }

        let fileMarkers = ["*** Add File: ", "*** Update File: ", "*** Delete File: "]
        var files: [ToolDiffFile] = []
        var currentPath: String?
        var currentLines: [ToolDiffLine] = []

        func flushFile() {
            guard currentPath != nil || !currentLines.isEmpty else { return }
            files.append(ToolDiffFile(path: currentPath, lines: currentLines))
            currentPath = nil
            currentLines = []
        }

        for line in patch.components(separatedBy: .newlines) {
            if let marker = fileMarkers.first(where: line.hasPrefix) {
                flushFile()
                currentPath = String(line.dropFirst(marker.count))
                continue
            }
            if line.hasPrefix("*** Move to: ") {
                currentPath = String(line.dropFirst("*** Move to: ".count))
                continue
            }
            if line == "*** Begin Patch" || line == "*** End Patch" || line.hasPrefix("@@") {
                continue
            }

            if line.hasPrefix("+") {
                currentLines.append(ToolDiffLine(kind: .added, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                currentLines.append(ToolDiffLine(kind: .removed, text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                currentLines.append(ToolDiffLine(kind: .context, text: String(line.dropFirst())))
            }
        }
        flushFile()

        return files.isEmpty ? nil : ToolDiff(files: files)
    }

    /// Decides whether the output is an error from the exit code near its start (`Exit code: 1`,
    /// `Process exited with code 1`). Rollouts carry no flag equivalent to Claude's `is_error`.
    private static func looksLikeError(_ output: String) -> Bool {
        guard let regex = exitCodeRegex else { return false }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
            let codeRange = Range(match.range(at: 1), in: output)
        else { return false }
        return Int(output[codeRange]) != 0
    }

    private static let exitCodeRegex = try? NSRegularExpression(
        pattern: #"(?:Exit code|exited with code)[: ]+(\d+)"#
    )

    private static func iso8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
