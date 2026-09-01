import Foundation

// MARK: - Event associated-value types

public struct SessionInfo: Sendable {
    public let sessionId: String
    public let model: String?
    public let cwd: String?
    public let transcriptPath: String?
    public let source: String?
}

public struct SessionStopInfo: Sendable {
    public let sessionId: String
    public let lastAssistantMessage: String?
    public let transcriptPath: String?
    /// Present when a Stop hook fires inside a child agent. A root session started
    /// with `--agent` can have `agent_type`, but it does not have `agent_id`.
    public let agentId: String?
    /// Claude Code 2.1.145+ includes every in-flight task in this array.
    public let backgroundTaskCount: Int
    /// The subset of `backgroundTaskCount` that keeps the current turn going: subagents and
    /// teammates. Every other task type (`shell`, `monitor`, `workflow`, MCP tasks) runs
    /// detached while the session already sits at the user's input prompt, so it must not
    /// hold the session back from completing.
    public let agentBackgroundTaskCount: Int
    /// Scheduled work that can wake the session after the current response.
    public let sessionCronCount: Int

    public var hasPendingWork: Bool {
        agentBackgroundTaskCount > 0 || sessionCronCount > 0
    }
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
    public let toolName: String
    public let error: String
}

public struct SubagentStartInfo: Sendable {
    public let sessionId: String
    public let agentType: String
    /// `agent_id` for both Claude and Codex (Claude sometimes uses `subagent_id`). Without it, the run falls back to FIFO matching.
    public let agentId: String?
}

public struct SubagentStopInfo: Sendable {
    public let sessionId: String
    public let agentId: String?
    public let agentType: String?
    /// Codex's `agent_transcript_path`. Stored only; never parsed, since it duplicates the parent history.
    public let agentTranscriptPath: String?
}

public struct TaskCreatedInfo: Sendable {
    /// Whether this came from the TaskCreate tool or the first-class TaskCreated hook.
    public enum Source: Sendable, Equatable {
        case tool
        case hook
    }

    public let sessionId: String
    public let subject: String
    public let description: String
    /// Non-nil only for the hook path (`source == .hook`); the tool path does not know the ID yet.
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

/// An authoritative task-list snapshot emitted by a planning tool.
///
/// Both Codex `update_plan` and Claude Code `TodoWrite` are normalized to this
/// shape at the event boundary. Consumers therefore do not need to know either
/// tool's input schema.
public struct TaskListSnapshotInfo: Sendable {
    public struct Item: Equatable, Sendable {
        public let subject: String
        public let status: AgentTask.Status
        public let description: String?

        public init(subject: String, status: AgentTask.Status, description: String? = nil) {
            self.subject = subject
            self.status = status
            self.description = description
        }
    }

    public let sessionId: String
    public let items: [Item]

    public init(sessionId: String, items: [Item]) {
        self.sessionId = sessionId
        self.items = items
    }
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
    /// The agent-provided tool invocation ID. Nil when `toolUseId` had to be
    /// synthesized solely to key the deferred hook response.
    public let toolInvocationId: String?
    public let toolUseId: String
}

public struct AskQuestionInfo: Sendable {
    public enum Delivery: Sendable, Equatable {
        /// PreToolUse or another observe-only route.
        case observation
        /// PermissionRequest owns the deferred response channel and may replace its observation.
        case responseChannel
    }

    public let sessionId: String
    public let toolUseId: String
    public let questions: [Question]
    public let delivery: Delivery

    public init(
        sessionId: String,
        toolUseId: String,
        questions: [Question],
        delivery: Delivery = .observation
    ) {
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.questions = questions
        self.delivery = delivery
    }

    /// A single question. Claude Code's AskUserQuestion can send 1-4 at once.
    public struct Question: Sendable, Identifiable, Hashable {
        public let question: String
        public let header: String?
        public let multiSelect: Bool
        public let options: [Option]
        /// Key expected by the response protocol.
        ///
        /// Claude Code identifies answers by the question text. Codex App Server
        /// supplies a separate stable question id. Keeping that distinction in
        /// the shared model lets the same banner render either protocol without
        /// rewriting a displayed question into a transport key.
        public let responseKey: String
        /// Whether a free-form answer is accepted in addition to listed options.
        public let allowsOther: Bool
        /// Whether free-form input should be obscured while it is being entered.
        public let isSecret: Bool

        public var id: String { responseKey }

        public init(
            question: String,
            header: String?,
            multiSelect: Bool,
            options: [Option],
            responseKey: String? = nil,
            allowsOther: Bool = true,
            isSecret: Bool = false
        ) {
            self.question = question
            self.header = header
            self.multiSelect = multiSelect
            self.options = options
            self.responseKey = responseKey ?? question
            self.allowsOther = allowsOther
            self.isSecret = isSecret
        }
    }

    /// One option. `label` is both the displayed text and the response value; `description` adds detail.
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
    /// `prompt` is non-nil only when the UserPromptSubmit hook payload carries it;
    /// otherwise the caller falls back to reading the transcript.
    case userPrompt(sessionId: String, prompt: String?)
    case toolStarted(ToolStartInfo)
    case toolCompleted(ToolEndInfo)
    case toolFailed(ToolFailInfo)
    case permissionRequested(PermissionInfo)
    case notification(sessionId: String, type: String, message: String)
    /// Stop (the current response ended). This is not necessarily a user-input boundary:
    /// background agents can still be running and wake the root session again.
    case sessionIdle(SessionStopInfo)
    case sessionEnded(String)
    case subagentStopped(SubagentStopInfo)
    case askQuestion(AskQuestionInfo)
    case subagentStarted(SubagentStartInfo)
    case compacting(sessionId: String)
    case compactingDone(sessionId: String)
    /// `errorType` is Claude Code's error enum (rate_limit / invalid_request / …).
    /// `details` is the optional free-text `error_details`, kept for the log — the enum alone
    /// does not say which request failed.
    case stopFailure(sessionId: String, errorType: String, details: String?)
    case taskCreated(TaskCreatedInfo)
    case taskCompleted(TaskCompletedInfo)
    case taskUpdated(sessionId: String, taskId: String, status: String)
    case taskListReplaced(TaskListSnapshotInfo)
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
            let prompt = json["prompt"] as? String
            return .userPrompt(sessionId: sessionId, prompt: prompt)

        case "PreToolUse":
            let toolName = json["tool_name"] as? String ?? ""
            let toolUseId = uniqueToolUseId(from: json)
            let rawInput = json["tool_input"] as? [String: Any] ?? [:]

            // Claude's AskUserQuestion and Codex's request_user_input share the
            // same display model. Codex PreToolUse remains observe-only: its
            // hook response is not the JSON-RPC response owned by App Server.
            if toolName == "AskUserQuestion" || toolName == "request_user_input" {
                guard let questions = parseAskQuestions(rawInput: rawInput) else { return .unknown }
                return .askQuestion(
                    AskQuestionInfo(
                        sessionId: sessionId, toolUseId: toolUseId, questions: questions
                    ))
            }

            // TaskCreate / TaskUpdate — task management tools
            if toolName == "TaskCreate" {
                let subject = rawInput["subject"] as? String ?? ""
                let description = rawInput["description"] as? String ?? ""
                return .taskCreated(
                    TaskCreatedInfo(
                        sessionId: sessionId, subject: subject, description: description,
                        taskId: nil, assignee: nil, teamName: nil, source: .tool
                    ))
            }
            if toolName == "TaskUpdate" {
                let taskId = rawInput["taskId"] as? String ?? ""
                let status = rawInput["status"] as? String ?? ""
                return .taskUpdated(sessionId: sessionId, taskId: taskId, status: status)
            }
            if toolName == "update_plan", let items = parseCodexPlan(rawInput: rawInput) {
                return .taskListReplaced(
                    TaskListSnapshotInfo(sessionId: sessionId, items: items)
                )
            }
            if toolName == "TodoWrite", let items = parseClaudeTodos(rawInput: rawInput) {
                return .taskListReplaced(
                    TaskListSnapshotInfo(sessionId: sessionId, items: items)
                )
            }

            let toolInput = rawInput.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
            let summary = ToolSummary.generate(toolName: toolName, toolInput: toolInput)
            return .toolStarted(
                ToolStartInfo(
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
                toolName: json["tool_name"] as? String ?? "",
                error: error
            )
            return .toolFailed(info)

        case "PermissionRequest":
            let toolName = json["tool_name"] as? String ?? ""
            // Claude Code's PermissionRequest hook input carries no tool_use_id; unlike PreToolUse,
            // it is not put into hookInput. Falling back to an empty string would make every
            // PermissionRequest share the pending key "", so addPending's first-writer-wins rule
            // would reject every subsequent request. Instead a unique local ID is generated per
            // request and used to tie the UI's pending display to the socket response. Its actual
            // value does not matter, since responses are keyed by the hook process's connection.
            let toolInvocationId = (json["tool_use_id"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            }
            let toolUseId = toolInvocationId ?? uniqueToolUseId(from: json)
            let rawInput = json["tool_input"] as? [String: Any] ?? [:]

            // PermissionRequest is the canonical route for AskUserQuestion, and the only one where
            // the hook response can inject a tool_response.
            if toolName == "AskUserQuestion" {
                guard let questions = parseAskQuestions(rawInput: rawInput) else { return .unknown }
                return .askQuestion(
                    AskQuestionInfo(
                        sessionId: sessionId, toolUseId: toolUseId, questions: questions,
                        delivery: .responseChannel
                    ))
            }

            let toolInput = rawInput.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
            return .permissionRequested(
                PermissionInfo(
                    sessionId: sessionId, toolName: toolName,
                    toolInput: toolInput, toolInvocationId: toolInvocationId,
                    toolUseId: toolUseId
                ))

        case "Notification":
            // The kind arrives as `notification_type`; `type` is only a fallback for older
            // payloads. Reading `type` alone made every notification look untyped, which
            // silently disabled the `idle_prompt` handling downstream.
            let type =
                json["notification_type"] as? String
                ?? json["type"] as? String
                ?? ""
            let message = json["message"] as? String ?? ""
            return .notification(sessionId: sessionId, type: type, message: message)

        case "Stop":
            // Claude Code 2.1.145+ includes background_tasks/session_crons specifically so
            // consumers can distinguish "done" from "paused until background work wakes me".
            // Codex puts the final response text in the payload too, though it can be null.
            let lastMessage = (json["last_assistant_message"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            }
            let agentId = (json["agent_id"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            }
            let backgroundTasks = json["background_tasks"] as? [Any] ?? []
            return .sessionIdle(
                SessionStopInfo(
                    sessionId: sessionId,
                    lastAssistantMessage: lastMessage,
                    transcriptPath: json["transcript_path"] as? String,
                    agentId: agentId,
                    backgroundTaskCount: backgroundTasks.count,
                    agentBackgroundTaskCount: agentBackgroundTaskCount(in: backgroundTasks),
                    sessionCronCount: (json["session_crons"] as? [Any])?.count ?? 0
                ))

        case "TeammateIdle":
            // With agent teams enabled in Claude Code 2.1, this can arrive instead of Stop.
            return .teammateIdle(
                TeammateIdleInfo(
                    sessionId: sessionId,
                    teamName: json["team_name"] as? String,
                    teammateName: json["teammate_name"] as? String,
                    teammateSessionId: json["teammate_session_id"] as? String
                ))

        case "SubagentStart":
            let agentType = json["agent_type"] as? String ?? "unknown"
            let agentId = json["agent_id"] as? String ?? json["subagent_id"] as? String
            return .subagentStarted(
                SubagentStartInfo(
                    sessionId: sessionId, agentType: agentType, agentId: agentId
                ))

        case "SubagentStop":
            let agentId = json["agent_id"] as? String ?? json["subagent_id"] as? String
            return .subagentStopped(
                SubagentStopInfo(
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
            return .stopFailure(
                sessionId: sessionId,
                errorType: errorType,
                details: json["error_details"] as? String
            )

        case "TaskCreated":
            // First-class event in Claude Code 2.1+, a separate route from the TaskCreate tool.
            return .taskCreated(
                TaskCreatedInfo(
                    sessionId: sessionId,
                    subject: json["task_title"] as? String ?? "",
                    description: json["task_description"] as? String ?? "",
                    taskId: json["task_id"] as? String,
                    assignee: json["assigned_to"] as? String,
                    teamName: json["team_name"] as? String,
                    source: .hook
                ))

        case "TaskCompleted":
            return .taskCompleted(
                TaskCompletedInfo(
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

    /// `permission_mode` may accompany any event type. Since it is not guaranteed which events
    /// carry it, it is not part of any `ClaudeEvent` case and is instead pulled defensively out
    /// of the raw JSON each time.
    public static func permissionMode(from json: [String: Any]) -> String? {
        json["permission_mode"] as? String
    }

    /// Returns a tool_use_id usable as the key for pending registration and UI correlation.
    /// Falls back to a unique local ID both when the payload has none (PermissionRequest never
    /// does) and when it is present but empty. Using an empty string as the key would collide
    /// across all requests, and addPending's first-writer-wins rule would drop the rest.
    private static func uniqueToolUseId(from json: [String: Any]) -> String {
        if let id = json["tool_use_id"] as? String, !id.isEmpty { return id }
        return UUID().uuidString
    }

    /// Task types in `background_tasks` that mean the turn itself is still going: another
    /// agent is working under this session and its result comes back into the same turn.
    ///
    /// Everything else Claude registers there — `shell` (a backgrounded Bash command),
    /// `monitor`, `workflow`, MCP tasks — is detached work. The session is already back at
    /// the user's input prompt, so treating those as pending would pin the card to
    /// "Thinking" for as long as the task lives. A backgrounded server that never exits
    /// pinned it forever.
    private static let turnContinuingTaskTypes: Set<String> = ["subagent", "teammate"]

    /// Counts the entries of a Stop payload's `background_tasks` that hold the turn open.
    ///
    /// An allow-list rather than a deny-list of detached types, deliberately: the two names
    /// above are the ones the payload and the tests actually confirm, while the detached
    /// discriminants are only known from a schema example. Guessing one of those wrong
    /// would bring back the bug this rule exists to prevent.
    ///
    /// So an unrecognised type is treated as detached and lets the turn complete. Being
    /// wrong that way costs one early completion notification and sound, which cannot be
    /// taken back, though the card itself returns to running on the next tool event. Being
    /// wrong the other way defers the Stop with nothing left to re-check it, which pins the
    /// card to "Thinking" until the app restarts. A recoverable card and one stray chime
    /// beat a card that never recovers. Tracked subagents are counted separately
    /// (`runningSubagentCount`), so this list only has to cover a missed SubagentStart. An
    /// entry with no readable `type` at all is a malformed payload, not a new task type,
    /// and still counts as pending.
    private static func agentBackgroundTaskCount(in tasks: [Any]) -> Int {
        tasks.filter { task in
            guard let task = task as? [String: Any],
                let type = task["type"] as? String, !type.isEmpty
            else { return true }
            return turnContinuingTaskTypes.contains(type)
        }.count
    }

    /// Parses `tool_input.questions` into typed `[AskQuestionInfo.Question]`.
    /// Returns `nil` if no question could be parsed. Called from both the PreToolUse and
    /// PermissionRequest paths.
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
                options: options,
                responseKey: q["id"] as? String,
                allowsOther: q["isOther"] as? Bool ?? (options.isEmpty || toolAllowsOther(q)),
                isSecret: q["isSecret"] as? Bool ?? false
            )
        }
        return questions.isEmpty ? nil : questions
    }

    /// Codex CLI's current request_user_input payload omits `isOther`, but an
    /// option-less prompt is necessarily free-form. Keep this helper narrow so
    /// Claude's traditional implicit Other row remains unchanged.
    private static func toolAllowsOther(_ question: [String: Any]) -> Bool {
        question["id"] != nil
    }

    /// Codex uses `step`; Claude Code uses `content` plus an optional
    /// present-progress `activeForm`. Only structurally valid arrays are
    /// snapshots: a malformed payload must not erase a previously known plan.
    private static func parseCodexPlan(rawInput: [String: Any]) -> [TaskListSnapshotInfo.Item]? {
        guard let plan = rawInput["plan"] as? [[String: Any]] else { return nil }
        let items: [TaskListSnapshotInfo.Item] = plan.compactMap { item in
            guard let subject = nonEmptyString(item["step"]),
                let status = taskStatus(item["status"])
            else { return nil }
            return TaskListSnapshotInfo.Item(subject: subject, status: status)
        }
        return items.count == plan.count ? items : nil
    }

    private static func parseClaudeTodos(rawInput: [String: Any]) -> [TaskListSnapshotInfo.Item]? {
        guard let todos = rawInput["todos"] as? [[String: Any]] else { return nil }
        let items: [TaskListSnapshotInfo.Item] = todos.compactMap { item in
            guard let subject = nonEmptyString(item["content"]),
                let status = taskStatus(item["status"])
            else { return nil }
            return TaskListSnapshotInfo.Item(
                subject: subject,
                status: status,
                description: nonEmptyString(item["activeForm"])
            )
        }
        return items.count == todos.count ? items : nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func taskStatus(_ value: Any?) -> AgentTask.Status? {
        guard let rawValue = value as? String else { return nil }
        switch rawValue {
        case "pending":
            return .pending
        case "in_progress", "inProgress":
            return .inProgress
        case "completed":
            return .completed
        default:
            return nil
        }
    }
}
