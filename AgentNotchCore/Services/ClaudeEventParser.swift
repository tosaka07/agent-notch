import Foundation

// MARK: - Event associated-value types

public struct SessionInfo: Sendable {
    public let sessionId: String
    public let model: String?
    public let cwd: String?
    public let transcriptPath: String?
    public let source: String?
}

public struct ToolStartInfo: Sendable {
    public let sessionId: String
    public let toolName: String
    public let toolUseId: String
    public let toolInput: [String: String]
    public let summary: String
}

public struct ToolEndInfo: Sendable {
    public let sessionId: String
    public let toolUseId: String
    public let toolName: String
}

public struct ToolFailInfo: Sendable {
    public let sessionId: String
    public let toolUseId: String
    public let error: String
}

public struct PermissionInfo: Sendable {
    public let sessionId: String
    public let toolName: String
    public let toolInput: [String: String]
    public let toolUseId: String
}

public struct AskQuestionInfo: Sendable {
    public let sessionId: String
    public let toolUseId: String
    public let question: String
    public let options: [String]
}

// MARK: - ClaudeEvent

public enum ClaudeEvent: Sendable {
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
    case askQuestion(AskQuestionInfo)
    case compacting(sessionId: String)
    case unknown
}

// MARK: - Parser

public enum ClaudeEventParser {
    public static func parse(_ json: [String: Any]) -> ClaudeEvent {
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

            // AskUserQuestion — special handling
            if toolName == "AskUserQuestion" {
                let questions = rawInput["questions"] as? [[String: Any]] ?? []
                let firstQ = questions.first
                let question = firstQ?["question"] as? String ?? "Question from Claude"
                let options = firstQ?["options"] as? [String] ?? []
                return .askQuestion(AskQuestionInfo(
                    sessionId: sessionId, toolUseId: toolUseId,
                    question: question, options: options
                ))
            }

            let toolInput = rawInput.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
            let summary = ToolSummary.generate(toolName: toolName, toolInput: toolInput)
            return .toolStarted(ToolStartInfo(
                sessionId: sessionId, toolName: toolName, toolUseId: toolUseId,
                toolInput: toolInput, summary: summary
            ))

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
            let toolUseId = json["tool_use_id"] as? String ?? ""
            let rawInput = json["tool_input"] as? [String: Any] ?? [:]
            let toolInput = rawInput.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
            return .permissionRequested(PermissionInfo(
                sessionId: sessionId, toolName: toolName,
                toolInput: toolInput, toolUseId: toolUseId
            ))

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
