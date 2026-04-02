import Foundation

// MARK: - Event associated-value types

struct SessionInfo: Sendable {
    let sessionId: String
    let model: String?
    let cwd: String?
    let transcriptPath: String?
    let source: String?
}

struct ToolStartInfo: Sendable {
    let sessionId: String
    let toolName: String
    let toolUseId: String
    let toolInput: [String: String]
    let summary: String
}

struct ToolEndInfo: Sendable {
    let sessionId: String
    let toolUseId: String
    let toolName: String
}

struct ToolFailInfo: Sendable {
    let sessionId: String
    let toolUseId: String
    let error: String
}

struct PermissionInfo: Sendable {
    let sessionId: String
    let toolName: String
    let toolInput: [String: String]
}

// MARK: - ClaudeEvent

enum ClaudeEvent: Sendable {
    case sessionStarted(SessionInfo)
    case userPrompt(sessionId: String)
    case toolStarted(ToolStartInfo)
    case toolCompleted(ToolEndInfo)
    case toolFailed(ToolFailInfo)
    case permissionRequested(PermissionInfo)
    case notification(sessionId: String, type: String, message: String)
    case sessionIdle(String)
    case sessionEnded(String)
    case subagentStopped(sessionId: String)
    case compacting(sessionId: String)
    case unknown
}

// MARK: - Parser

enum ClaudeEventParser {
    static func parse(_ json: [String: Any]) -> ClaudeEvent {
        guard let eventType = json["hook_event_name"] as? String else {
            return .unknown
        }

        let sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? "unknown"

        switch eventType {
        case "SessionStart":
            let info = SessionInfo(
                sessionId: sessionId,
                model: json["model"] as? String,
                cwd: json["cwd"] as? String,
                transcriptPath: json["transcript_path"] as? String,
                source: json["source"] as? String
            )
            return .sessionStarted(info)

        case "UserPromptSubmit":
            return .userPrompt(sessionId: sessionId)

        case "PreToolUse":
            let toolName = json["tool_name"] as? String ?? ""
            let toolUseId = json["tool_use_id"] as? String ?? UUID().uuidString
            let rawInput = json["tool_input"] as? [String: Any] ?? [:]
            let toolInput = rawInput.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
            let summary = ToolSummary.generate(toolName: toolName, toolInput: toolInput)
            let info = ToolStartInfo(
                sessionId: sessionId,
                toolName: toolName,
                toolUseId: toolUseId,
                toolInput: toolInput,
                summary: summary
            )
            return .toolStarted(info)

        case "PostToolUse":
            let toolName = json["tool_name"] as? String ?? ""
            let toolUseId = json["tool_use_id"] as? String ?? ""
            let info = ToolEndInfo(
                sessionId: sessionId,
                toolUseId: toolUseId,
                toolName: toolName
            )
            return .toolCompleted(info)

        case "PostToolUseFailure":
            let toolUseId = json["tool_use_id"] as? String ?? ""
            let error = json["error"] as? String ?? "unknown error"
            let info = ToolFailInfo(
                sessionId: sessionId,
                toolUseId: toolUseId,
                error: error
            )
            return .toolFailed(info)

        case "PermissionRequest":
            let toolName = json["tool_name"] as? String ?? ""
            let rawInput = json["tool_input"] as? [String: Any] ?? [:]
            let toolInput = rawInput.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
            let info = PermissionInfo(
                sessionId: sessionId,
                toolName: toolName,
                toolInput: toolInput
            )
            return .permissionRequested(info)

        case "Notification":
            let type = json["type"] as? String ?? ""
            let message = json["message"] as? String ?? ""
            return .notification(sessionId: sessionId, type: type, message: message)

        case "Stop":
            return .sessionIdle(sessionId)

        case "SubagentStop":
            return .subagentStopped(sessionId: sessionId)

        case "SessionEnd":
            return .sessionEnded(sessionId)

        case "PreCompact":
            return .compacting(sessionId: sessionId)

        default:
            return .unknown
        }
    }
}
