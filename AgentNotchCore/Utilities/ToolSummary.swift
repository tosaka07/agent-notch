import Foundation

public enum ToolSummary {
    public static func generate(toolName: String, toolInput: [String: String]) -> String {
        switch toolName.lowercased() {
        case "bash":
            if let command = toolInput["command"] {
                return command.count > 30
                    ? String(command.prefix(30)) + "..."
                    : command
            }
            return "bash"

        case "edit", "write", "read":
            if let path = toolInput["file_path"] ?? toolInput["path"] {
                return (path as NSString).lastPathComponent
            }
            return toolName

        case "grep":
            if let pattern = toolInput["pattern"] {
                return "\"\(pattern)\""
            }
            return "grep"

        case "glob":
            if let pattern = toolInput["pattern"] {
                return pattern
            }
            return "glob"

        case "websearch":
            if let query = toolInput["query"] {
                return query.count > 20
                    ? String(query.prefix(20)) + "..."
                    : query
            }
            return "search"

        case "webfetch":
            if let url = toolInput["url"],
                let components = URLComponents(string: url),
                let host = components.host
            {
                return host
            }
            return "fetch"

        case "agent":
            if let subType = toolInput["subagent_type"] {
                return subType
            }
            return "agent"

        default:
            if toolName.hasPrefix("mcp__") {
                let parts = toolName.dropFirst(5).split(separator: "__", maxSplits: 1)
                if parts.count == 2 {
                    return "\(parts[0]):\(parts[1])"
                }
            }
            return toolName
        }
    }
}
