import Foundation

public struct TokenUsage: Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var totalTokens: Int { inputTokens + outputTokens }
    public var cachedTokens: Int { cacheCreationTokens + cacheReadTokens }
}

public enum TranscriptParser {
    /// Accumulates usage from a transcript.
    ///
    /// Usage is nested under **`message.usage`**; there is no top-level `usage`.
    ///
    /// One assistant message is split across several lines, one per content block (thinking, text,
    /// and tool_use appear as three lines sharing a `message.id`), so summing them naively inflates
    /// the total two- to threefold. Keyed on `(message.id, requestId)`, **the last line wins**:
    /// earlier lines are streaming placeholders whose output_tokens are too low.
    public static func parseCumulativeUsage(at path: String) -> TokenUsage {
        // The Codex integration switch decides whether Codex's own files may be opened at all.
        guard CodexAccess.allowsTranscript(at: path) else { return TokenUsage() }
        // Codex rollout files use a different format (cumulative values in token_count events), so route them separately.
        if CodexTranscriptReader.isRollout(path: path) {
            return CodexTranscriptReader.parseCumulativeUsage(at: path)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else {
            return TokenUsage()
        }

        var latestByKey: [String: TokenUsage] = [:]
        var keyOrder: [String] = []

        for line in content.components(separatedBy: .newlines) {
            guard line.contains("\"usage\""),
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let message = json["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else {
                continue
            }

            var entry = TokenUsage()
            entry.inputTokens = usage["input_tokens"] as? Int ?? 0
            entry.outputTokens = usage["output_tokens"] as? Int ?? 0
            entry.cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
            entry.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0

            let messageId = message["id"] as? String ?? ""
            let requestId = json["requestId"] as? String ?? ""
            let key =
                messageId.isEmpty && requestId.isEmpty
                ? UUID().uuidString  // A line with no key cannot be deduplicated, so count it as is.
                : "\(messageId):\(requestId)"

            if latestByKey.updateValue(entry, forKey: key) == nil {
                keyOrder.append(key)
            }
        }

        var total = TokenUsage()
        for key in keyOrder {
            guard let entry = latestByKey[key] else { continue }
            total.inputTokens += entry.inputTokens
            total.outputTokens += entry.outputTokens
            total.cacheCreationTokens += entry.cacheCreationTokens
            total.cacheReadTokens += entry.cacheReadTokens
        }
        return total
    }

    /// Extracts the session title from the transcript.
    /// Priority: customTitle (user-set via /rename) > slug (auto-generated).
    public static func sessionTitle(at path: String) -> String? {
        guard CodexAccess.allowsTranscript(at: path) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return nil }

        var slug: String?

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // customTitle takes priority — return immediately
            if json["type"] as? String == "custom-title",
                let title = json["customTitle"] as? String, !title.isEmpty
            {
                return title
            }

            // Capture slug from any entry (first occurrence is enough)
            if slug == nil, let s = json["slug"] as? String, !s.isEmpty {
                slug = s
            }
        }

        return slug
    }

    /// Returns the first and last user messages in a single pass over the file.
    /// Slash commands and system-injected messages are skipped.
    public static func userMessages(at path: String) -> (first: String?, last: String?) {
        guard CodexAccess.allowsTranscript(at: path) else { return (nil, nil) }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return (nil, nil) }

        var first: String?
        var last: String?

        for line in content.components(separatedBy: .newlines) {
            guard let text = extractUserMessage(from: line) else { continue }
            if first == nil { first = text }
            last = text
        }
        return (first, last)
    }

    public static func firstUserMessage(at path: String) -> String? {
        userMessages(at: path).first
    }

    public static func lastUserMessage(at path: String) -> String? {
        userMessages(at: path).last
    }

    /// Extracts a user message from one JSONL line, excluding slash commands and the like.
    private static func extractUserMessage(from line: some StringProtocol) -> String? {
        guard !line.isEmpty,
            let lineData = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            json["type"] as? String == "user",
            let message = json["message"] as? [String: Any]
        else { return nil }

        let text: String? = {
            if let s = message["content"] as? String, !s.isEmpty { return s }
            if let arr = message["content"] as? [[String: Any]] {
                for block in arr where block["type"] as? String == "text" {
                    if let s = block["text"] as? String, !s.isEmpty { return s }
                }
            }
            return nil
        }()

        guard let text else { return nil }
        return sanitizeUserPromptText(text)
    }

    /// Formats user input text for display.
    /// - Returns `nil` for slash commands and system-injected command tags, which are not displayed.
    /// - Replaces image reference blocks (`[Image: ...]`) with a marker.
    ///
    /// Public so the same formatting applies both to text extracted from a transcript and to the
    /// `prompt` carried directly in a UserPromptSubmit hook payload.
    public static func sanitizeUserPromptText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") { return nil }
        if trimmed.hasPrefix("<") && trimmed.contains("command") { return nil }
        return formatImageReferences(in: trimmed)
    }

    /// Hoisted to a static let to avoid recompiling the pattern on every call.
    private static let imageReferenceRegex = try? NSRegularExpression(
        pattern: #"\[Image:[^\]]*\]"#, options: [.caseInsensitive]
    )

    /// Replaces image reference blocks such as `[Image: source: /path/to/file]` with a marker.
    /// Several blocks collapse into a single marker with a count.
    private static func formatImageReferences(in text: String) -> String {
        guard let regex = imageReferenceRegex else {
            return text
        }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: mutable.length))
        guard !matches.isEmpty else { return text }

        let count = matches.count
        let marker =
            count == 1
            ? AppLocalization.localized("[Image]")
            : AppLocalization.localized("[Image ×\(count)]")
        // Replacing from the end keeps the earlier matches' ranges valid.
        // Only the first match becomes the marker; the rest are simply deleted.
        for (index, match) in matches.enumerated().reversed() {
            mutable.replaceCharacters(in: match.range, with: index == 0 ? marker : "")
        }

        let collapsed = mutable.replacingOccurrences(
            of: #"[ \t]{2,}"#, with: " ", options: .regularExpression,
            range: NSRange(location: 0, length: mutable.length)
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the last assistant text message from the transcript (for completion notifications).
    public static func lastAssistantMessage(at path: String) -> String? {
        guard CodexAccess.allowsTranscript(at: path) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8)
        else { return nil }

        for line in content.components(separatedBy: .newlines).reversed() {
            guard !line.isEmpty,
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                json["type"] as? String == "assistant",
                let message = json["message"] as? [String: Any],
                let contentArray = message["content"] as? [[String: Any]]
            else { continue }

            for block in contentArray where block["type"] as? String == "text" {
                if let text = block["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    // MARK: - Waiting for appends to finish

    /// How many times, and how often, to poll while waiting for transcript appends to finish.
    public static let settleAttempts = 6
    public static let settleInterval: Duration = .milliseconds(80)

    /// Waits until the transcript's size stops changing, capped at `settleAttempts × settleInterval`.
    ///
    /// A hook can fire **before** the transcript has been appended to. Reading without waiting
    /// misses the last entry and yields **the previous one** instead — observed both in completion
    /// notifications and in the prompt on session cards. There is no way to be told "the append is
    /// done", so two consecutive identical sizes are taken to mean the write finished.
    ///
    /// # Limitation
    /// Only size changes are observed, so **a write that has not started yet cannot be waited for**;
    /// if the first two samples match, this returns immediately. Callers where the write may start
    /// after a delay should pass `minimumWait` to pause before sampling.
    ///
    /// Keep the cap around half a second: noticing late is sometimes worse than showing stale content.
    public static func waitUntilSettled(at path: String, minimumWait: Duration = .zero) async {
        guard CodexAccess.allowsTranscript(at: path) else { return }
        if minimumWait > .zero { try? await Task.sleep(for: minimumWait) }
        var previousSize: Int?
        for _ in 0..<settleAttempts {
            let size = fileSize(at: path)
            if let previousSize, size == previousSize { return }
            previousSize = size
            try? await Task.sleep(for: settleInterval)
        }
    }

    private static func fileSize(at path: String) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return 0
        }
        return attributes[.size] as? Int ?? 0
    }
}
