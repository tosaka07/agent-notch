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
    public static func parseCumulativeUsage(at path: String) -> TokenUsage {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8)
        else {
            return TokenUsage()
        }

        var total = TokenUsage()

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let usage = json["usage"] as? [String: Any]
            else {
                continue
            }

            total.inputTokens += usage["input_tokens"] as? Int ?? 0
            total.outputTokens += usage["output_tokens"] as? Int ?? 0
            total.cacheCreationTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
            total.cacheReadTokens += usage["cache_read_input_tokens"] as? Int ?? 0
        }

        return total
    }

    /// Extracts the session title from the transcript.
    /// Priority: customTitle (user-set via /rename) > slug (auto-generated).
    public static func sessionTitle(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var slug: String?

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // customTitle takes priority — return immediately
            if json["type"] as? String == "custom-title",
               let title = json["customTitle"] as? String, !title.isEmpty {
                return title
            }

            // Capture slug from any entry (first occurrence is enough)
            if slug == nil, let s = json["slug"] as? String, !s.isEmpty {
                slug = s
            }
        }

        return slug
    }

    /// 最初と最後のユーザーメッセージを 1 回のファイル読み込みで取得。
    /// スラッシュコマンドやシステム注入メッセージはスキップ。
    public static func userMessages(at path: String) -> (first: String?, last: String?) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return (nil, nil) }

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

    /// JSONL の 1 行からユーザーメッセージを抽出。スラッシュコマンド等を除外。
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") { return nil }
        if trimmed.hasPrefix("<") && trimmed.contains("command") { return nil }
        return trimmed
    }

    /// Returns the last assistant text message from the transcript (for completion notifications).
    public static func lastAssistantMessage(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return nil }

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
}
