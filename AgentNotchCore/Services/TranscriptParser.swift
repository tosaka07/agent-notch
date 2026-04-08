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
