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

public struct SubagentStartInfo: Sendable {
    public let sessionId: String
    public let agentType: String
    /// Claude/Codex どちらも `agent_id`（Claude は `subagent_id` の場合あり）。無ければ FIFO フォールバック対象。
    public let agentId: String?
}

public struct SubagentStopInfo: Sendable {
    public let sessionId: String
    public let agentId: String?
    public let agentType: String?
    /// Codex の `agent_transcript_path`。保持のみ（親履歴複製の罠があるため解析はしない）。
    public let agentTranscriptPath: String?
}

public struct TaskCreatedInfo: Sendable {
    /// tool（TaskCreate）経由か、first-class の TaskCreated hook 経由か。
    public enum Source: Sendable, Equatable {
        case tool
        case hook
    }

    public let sessionId: String
    public let subject: String
    public let description: String
    /// hook 経由（`source == .hook`）のみ non-nil。tool 経由は未確定なので nil。
    public let taskId: String?
    public let assignee: String?
    public let teamName: String?
    public let source: Source
}

public struct TaskCompletedInfo: Sendable {
    public let sessionId: String
    public let taskId: String?
    public let subject: String?
    public let completedBy: String?
    public let teamName: String?
}

public struct TeammateIdleInfo: Sendable {
    public let sessionId: String
    public let teamName: String?
    public let teammateName: String?
    public let teammateSessionId: String?
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
    public let questions: [Question]

    public init(sessionId: String, toolUseId: String, questions: [Question]) {
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.questions = questions
    }

    /// 1 問分の質問。Claude Code の AskUserQuestion は 1-4 問まで同時に送れる。
    public struct Question: Sendable, Identifiable, Hashable {
        public let question: String
        public let header: String?
        public let multiSelect: Bool
        public let options: [Option]

        /// 質問文を ID として使う（同一 bundle 内で重複しない前提）。
        public var id: String { question }

        public init(question: String, header: String?, multiSelect: Bool, options: [Option]) {
            self.question = question
            self.header = header
            self.multiSelect = multiSelect
            self.options = options
        }
    }

    /// 選択肢 1 つ。`label` が表示文字列かつ応答値、`description` は補足説明。
    public struct Option: Sendable, Identifiable, Hashable {
        public let label: String
        public let description: String?
        public let preview: String?

        public var id: String { label }

        public init(label: String, description: String?, preview: String?) {
            self.label = label
            self.description = description
            self.preview = preview
        }
    }
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
    case subagentStopped(SubagentStopInfo)
    case askQuestion(AskQuestionInfo)
    case subagentStarted(SubagentStartInfo)
    case compacting(sessionId: String)
    case compactingDone(sessionId: String)
    case stopFailure(sessionId: String, errorType: String)
    case taskCreated(TaskCreatedInfo)
    case taskCompleted(TaskCompletedInfo)
    case taskUpdated(sessionId: String, taskId: String, status: String)
    case teammateIdle(TeammateIdleInfo)
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
                guard let questions = parseAskQuestions(rawInput: rawInput) else { return .unknown }
                return .askQuestion(AskQuestionInfo(
                    sessionId: sessionId, toolUseId: toolUseId, questions: questions
                ))
            }

            // TaskCreate / TaskUpdate — task 管理ツール
            if toolName == "TaskCreate" {
                let subject = rawInput["subject"] as? String ?? ""
                let description = rawInput["description"] as? String ?? ""
                return .taskCreated(TaskCreatedInfo(
                    sessionId: sessionId, subject: subject, description: description,
                    taskId: nil, assignee: nil, teamName: nil, source: .tool
                ))
            }
            if toolName == "TaskUpdate" {
                let taskId = rawInput["taskId"] as? String ?? ""
                let status = rawInput["status"] as? String ?? ""
                return .taskUpdated(sessionId: sessionId, taskId: taskId, status: status)
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

            // AskUserQuestion は PermissionRequest 経由で届くのが正規ルート。
            // hook response 側で tool_response を注入できる唯一の経路。
            if toolName == "AskUserQuestion" {
                guard let questions = parseAskQuestions(rawInput: rawInput) else { return .unknown }
                return .askQuestion(AskQuestionInfo(
                    sessionId: sessionId, toolUseId: toolUseId, questions: questions
                ))
            }

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

        case "TeammateIdle":
            // Claude Code 2.1 の agent teams 有効時は Stop の代わりにこれが飛ぶことがある。
            return .teammateIdle(TeammateIdleInfo(
                sessionId: sessionId,
                teamName: json["team_name"] as? String,
                teammateName: json["teammate_name"] as? String,
                teammateSessionId: json["teammate_session_id"] as? String
            ))

        case "SubagentStart":
            let agentType = json["agent_type"] as? String ?? "unknown"
            let agentId = json["agent_id"] as? String ?? json["subagent_id"] as? String
            return .subagentStarted(SubagentStartInfo(
                sessionId: sessionId, agentType: agentType, agentId: agentId
            ))

        case "SubagentStop":
            let agentId = json["agent_id"] as? String ?? json["subagent_id"] as? String
            return .subagentStopped(SubagentStopInfo(
                sessionId: sessionId,
                agentId: agentId,
                agentType: json["agent_type"] as? String,
                agentTranscriptPath: json["agent_transcript_path"] as? String
            ))

        case "SessionEnd":
            return .sessionEnded(sessionId)

        case "PreCompact":
            return .compacting(sessionId: sessionId)

        case "PostCompact":
            return .compactingDone(sessionId: sessionId)

        case "StopFailure":
            let errorType = json["error"] as? String ?? "unknown"
            return .stopFailure(sessionId: sessionId, errorType: errorType)

        case "TaskCreated":
            // Claude Code 2.1+ の first-class イベント（TaskCreate ツール経由とは別経路）。
            return .taskCreated(TaskCreatedInfo(
                sessionId: sessionId,
                subject: json["task_title"] as? String ?? "",
                description: json["task_description"] as? String ?? "",
                taskId: json["task_id"] as? String,
                assignee: json["assigned_to"] as? String,
                teamName: json["team_name"] as? String,
                source: .hook
            ))

        case "TaskCompleted":
            return .taskCompleted(TaskCompletedInfo(
                sessionId: sessionId,
                taskId: json["task_id"] as? String,
                subject: json["task_title"] as? String,
                completedBy: json["completed_by"] as? String,
                teamName: json["team_name"] as? String
            ))

        default:
            return .unknown
        }
    }

    /// `tool_input.questions` を型付きの `[AskQuestionInfo.Question]` にパースする。
    /// 1 問も取れなければ `nil`。PreToolUse / PermissionRequest の両経路から呼ぶ。
    private static func parseAskQuestions(rawInput: [String: Any]) -> [AskQuestionInfo.Question]? {
        let rawQuestions = rawInput["questions"] as? [[String: Any]] ?? []
        let questions: [AskQuestionInfo.Question] = rawQuestions.compactMap { q in
            guard let text = q["question"] as? String else { return nil }
            let rawOptions = q["options"] as? [[String: Any]] ?? []
            let options: [AskQuestionInfo.Option] = rawOptions.compactMap { o in
                guard let label = o["label"] as? String else { return nil }
                return AskQuestionInfo.Option(
                    label: label,
                    description: o["description"] as? String,
                    preview: o["preview"] as? String
                )
            }
            return AskQuestionInfo.Question(
                question: text,
                header: q["header"] as? String,
                multiSelect: q["multiSelect"] as? Bool ?? false,
                options: options
            )
        }
        return questions.isEmpty ? nil : questions
    }
}
