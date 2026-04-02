import Foundation

public enum TranscriptReader {
    public static func read(path: String, tail: Int = 50) -> [ChatEntry] {
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
                    } else if blockType == "tool_use" {
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
