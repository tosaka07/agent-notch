import Foundation
import Testing

@testable import AgentNotchCore

@Suite("ClaudeEventParser Tests")
struct ClaudeEventParserTests {
    @Test("SessionStart maps to sessionStarted with correct fields")
    func sessionStart() {
        let json: [String: Any] = [
            "hook_event_name": "SessionStart",
            "session_id": "sess-001",
            "model": "claude-sonnet-4-20250514",
            "cwd": "/Users/dev/project",
            "transcript_path": "/tmp/transcript.jsonl",
            "source": "cli",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .sessionStarted(let info) = event else {
            Issue.record("Expected sessionStarted")
            return
        }
        #expect(info.sessionId == "sess-001")
        #expect(info.model == "claude-sonnet-4-20250514")
        #expect(info.cwd == "/Users/dev/project")
        #expect(info.transcriptPath == "/tmp/transcript.jsonl")
        #expect(info.source == "cli")
    }

    @Test("PreToolUse maps to toolStarted with summary from ToolSummary")
    func preToolUse() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "sess-001",
            "tool_name": "Edit",
            "tool_use_id": "tu-123",
            "tool_input": ["file_path": "/Users/dev/project/main.swift"],
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .toolStarted(let info) = event else {
            Issue.record("Expected toolStarted")
            return
        }
        #expect(info.sessionId == "sess-001")
        #expect(info.toolName == "Edit")
        #expect(info.toolUseId == "tu-123")
        #expect(info.summary == "main.swift")
    }

    @Test("Codex request_user_input PreToolUse maps to an observable question")
    func codexRequestUserInput() throws {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "thread-1",
            "tool_name": "request_user_input",
            "tool_use_id": "call-question",
            "tool_input": [
                "questions": [
                    [
                        "id": "target",
                        "header": "Target",
                        "question": "Where?",
                        "options": [
                            ["label": "Staging", "description": "Internal"]
                        ],
                    ]
                ]
            ],
        ]

        guard case .askQuestion(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected askQuestion")
            return
        }
        let question = try #require(info.questions.first)
        #expect(info.sessionId == "thread-1")
        #expect(info.toolUseId == "call-question")
        #expect(info.delivery == .observation)
        #expect(question.responseKey == "target")
        #expect(question.question == "Where?")
        #expect(question.options.first?.label == "Staging")
        #expect(question.allowsOther)
    }

    @Test("UserPromptSubmit maps to userPrompt with prompt field from payload")
    func userPromptSubmitWithPrompt() {
        let json: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "sess-003",
            "prompt": "Fix the auth bug",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .userPrompt(let sessionId, let prompt) = event else {
            Issue.record("Expected userPrompt")
            return
        }
        #expect(sessionId == "sess-003")
        #expect(prompt == "Fix the auth bug")
    }

    @Test("UserPromptSubmit maps to userPrompt with nil prompt when field missing")
    func userPromptSubmitWithoutPrompt() {
        let json: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "sess-004",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .userPrompt(let sessionId, let prompt) = event else {
            Issue.record("Expected userPrompt")
            return
        }
        #expect(sessionId == "sess-004")
        #expect(prompt == nil)
    }

    @Test("PermissionRequest maps correctly")
    func permissionRequest() {
        let json: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "sess-002",
            "tool_name": "Bash",
            "tool_input": ["command": "rm -rf /tmp/test"],
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .permissionRequested(let info) = event else {
            Issue.record("Expected permissionRequested")
            return
        }
        #expect(info.sessionId == "sess-002")
        #expect(info.toolName == "Bash")
        #expect(info.toolInput["command"] == "rm -rf /tmp/test")
        #expect(info.toolInvocationId == nil)
    }

    @Test("PermissionRequest without tool_use_id generates unique local ids")
    func permissionRequestGeneratesUniqueToolUseId() {
        // Claude Code's PermissionRequest hook input carries no tool_use_id. Falling
        // back to an empty string would make every request collide on the same pending
        // key, so each request must get a unique generated ID.
        let json: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "sess-002",
            "tool_name": "Bash",
            "tool_input": ["command": "ls"],
        ]
        guard case .permissionRequested(let first) = ClaudeEventParser.parse(json),
            case .permissionRequested(let second) = ClaudeEventParser.parse(json)
        else {
            Issue.record("Expected permissionRequested")
            return
        }
        #expect(!first.toolUseId.isEmpty)
        #expect(first.toolUseId != second.toolUseId)
        #expect(first.toolInvocationId == nil)
    }

    @Test("PermissionRequest with an empty tool_use_id also falls back to a unique id")
    func permissionRequestEmptyToolUseIdFallsBack() {
        // A tool_use_id that is present but empty is treated like a missing one:
        // an empty string as the pending key would make all requests collide.
        let json: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "sess-002",
            "tool_name": "Bash",
            "tool_use_id": "",
            "tool_input": ["command": "ls"],
        ]
        guard case .permissionRequested(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected permissionRequested")
            return
        }
        #expect(!info.toolUseId.isEmpty)
        #expect(info.toolInvocationId == nil)
    }

    @Test("PermissionRequest AskUserQuestion without tool_use_id generates a non-empty id")
    func askQuestionViaPermissionRequestGeneratesToolUseId() {
        let json: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "sess-002",
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [
                    [
                        "question": "Which?",
                        "options": [["label": "A"], ["label": "B"]],
                    ]
                ]
            ],
        ]
        guard case .askQuestion(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected askQuestion")
            return
        }
        #expect(!info.toolUseId.isEmpty)
        #expect(info.delivery == .responseChannel)
    }

    @Test("Stop maps to sessionIdle")
    func stop() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-003",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .sessionIdle(let info) = event else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(info.sessionId == "sess-003")
        // Claude's Stop hook has no last_assistant_message.
        #expect(info.lastAssistantMessage == nil)
        #expect(!info.hasPendingWork)
        #expect(info.agentId == nil)
    }

    @Test("Stop carries child identity and pending background work")
    func stopCarriesLifecycleContext() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-child",
            "transcript_path": "/tmp/child.jsonl",
            "agent_id": "agent-1",
            "background_tasks": [
                ["id": "task-1", "type": "subagent", "status": "running"],
                ["id": "task-2", "type": "teammate", "status": "running"],
            ],
            "session_crons": [
                ["id": "cron-1", "schedule": "0 9 * * 1-5"]
            ],
        ]
        guard case .sessionIdle(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(info.transcriptPath == "/tmp/child.jsonl")
        #expect(info.agentId == "agent-1")
        #expect(info.backgroundTaskCount == 2)
        #expect(info.agentBackgroundTaskCount == 2)
        #expect(info.sessionCronCount == 1)
        #expect(info.hasPendingWork)
    }

    /// A backgrounded Bash command outlives the turn — it is still registered when the
    /// session is back at the input prompt, and one that never exits (a server, a log
    /// tail) would otherwise keep the session from ever completing.
    @Test("A backgrounded shell task is not pending work")
    func stopIgnoresDetachedShellTasks() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-shell",
            "background_tasks": [
                ["id": "task-1", "type": "shell", "status": "running"],
                ["id": "task-2", "type": "monitor", "status": "running"],
            ],
            "session_crons": [],
        ]
        guard case .sessionIdle(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(info.backgroundTaskCount == 2)
        #expect(info.agentBackgroundTaskCount == 0)
        #expect(!info.hasPendingWork)
    }

    /// An unrecognised task type errs toward waiting: a premature completion chime is
    /// worse than a card that settles one Stop later.
    @Test("An untyped background task still counts as pending work")
    func stopTreatsUnknownTaskTypesAsPending() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-unknown",
            "background_tasks": [
                ["id": "task-1", "status": "running"]
            ],
        ]
        guard case .sessionIdle(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(info.agentBackgroundTaskCount == 1)
        #expect(info.hasPendingWork)
    }

    /// Codex's Stop hook ships the final response text in its payload. Since Codex
    /// transcripts are not in Claude's format, this is the only source for the
    /// completion message.
    @Test("Codex Stop carries last_assistant_message")
    func stopCarriesLastAssistantMessage() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-004",
            "last_assistant_message": "Added 3 tests.",
        ]
        guard case .sessionIdle(let info) = ClaudeEventParser.parse(json) else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(info.lastAssistantMessage == "Added 3 tests.")

        // An empty string normalizes to "absent" so it cannot clobber the default completion text.
        let empty: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-005",
            "last_assistant_message": "",
        ]
        guard case .sessionIdle(let emptyInfo) = ClaudeEventParser.parse(empty) else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(emptyInfo.lastAssistantMessage == nil)
    }

    @Test("Unknown event type maps to unknown")
    func unknownEvent() {
        let json: [String: Any] = [
            "hook_event_name": "SomeFutureEvent",
            "session_id": "sess-004",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .unknown = event else {
            Issue.record("Expected unknown")
            return
        }
    }

    @Test("Missing event key maps to unknown")
    func missingEventKey() {
        let json: [String: Any] = [
            "session_id": "sess-005"
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .unknown = event else {
            Issue.record("Expected unknown")
            return
        }
    }

    // MARK: - permission_mode (shared field)

    @Test("PermissionRequest for ExitPlanMode maps to permissionRequested (plan review)")
    func permissionRequestExitPlanMode() {
        let json: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "sess-050",
            "tool_name": "ExitPlanMode",
            "tool_input": ["plan": "1. Do X\n2. Do Y"],
            "permission_mode": "plan",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .permissionRequested(let info) = event else {
            Issue.record("Expected permissionRequested, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-050")
        #expect(info.toolName == "ExitPlanMode")
    }

    @Test("permissionMode(from:) reads the common permission_mode field")
    func permissionModeCommonField() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "sess-051",
            "tool_name": "Read",
            "permission_mode": "plan",
        ]
        #expect(ClaudeEventParser.permissionMode(from: json) == "plan")
    }

    @Test("permissionMode(from:) is nil when the field is absent")
    func permissionModeMissing() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "sess-052",
        ]
        #expect(ClaudeEventParser.permissionMode(from: json) == nil)
    }

    @Test(
        "PermissionMode(rawValue:) accepts all known Claude Code modes",
        arguments: ["default", "acceptEdits", "plan", "dontAsk", "bypassPermissions"]
    )
    func permissionModeRawValues(raw: String) {
        #expect(PermissionMode(rawValue: raw) != nil)
    }

    @Test("PreToolUse with TaskCreate maps to taskCreated")
    func taskCreate() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "sess-010",
            "tool_name": "TaskCreate",
            "tool_use_id": "tu-tc1",
            "tool_input": [
                "subject": "Fix auth validation",
                "description": "Add input validation to the auth module",
            ] as [String: Any],
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .taskCreated(let info) = event else {
            Issue.record("Expected taskCreated, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-010")
        #expect(info.subject == "Fix auth validation")
        #expect(info.description == "Add input validation to the auth module")
        #expect(info.taskId == nil)
        #expect(info.source == .tool)
    }

    @Test("PreToolUse with TaskUpdate maps to taskUpdated")
    func taskUpdate() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "sess-010",
            "tool_name": "TaskUpdate",
            "tool_use_id": "tu-tu1",
            "tool_input": [
                "taskId": "2",
                "status": "completed",
            ] as [String: Any],
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .taskUpdated(let sessionId, let taskId, let status) = event else {
            Issue.record("Expected taskUpdated, got \(event)")
            return
        }
        #expect(sessionId == "sess-010")
        #expect(taskId == "2")
        #expect(status == "completed")
    }

    // MARK: - SubagentStart / SubagentStop

    @Test("SubagentStart maps to subagentStarted with agent_id present")
    func subagentStartWithAgentId() {
        let json: [String: Any] = [
            "hook_event_name": "SubagentStart",
            "session_id": "sess-020",
            "agent_type": "Explore",
            "agent_id": "agent-abc",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .subagentStarted(let info) = event else {
            Issue.record("Expected subagentStarted, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-020")
        #expect(info.agentType == "Explore")
        #expect(info.agentId == "agent-abc")
    }

    @Test("SubagentStart falls back to subagent_id when agent_id is missing")
    func subagentStartFallsBackToSubagentId() {
        let json: [String: Any] = [
            "hook_event_name": "SubagentStart",
            "session_id": "sess-021",
            "agent_type": "code-reviewer",
            "subagent_id": "sub-xyz",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .subagentStarted(let info) = event else {
            Issue.record("Expected subagentStarted, got \(event)")
            return
        }
        #expect(info.agentId == "sub-xyz")
    }

    @Test("SubagentStart with no id fields maps agentId to nil")
    func subagentStartWithoutId() {
        let json: [String: Any] = [
            "hook_event_name": "SubagentStart",
            "session_id": "sess-022",
            "agent_type": "Explore",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .subagentStarted(let info) = event else {
            Issue.record("Expected subagentStarted, got \(event)")
            return
        }
        #expect(info.agentId == nil)
    }

    @Test("SubagentStop maps full Codex payload correctly")
    func subagentStopCodexFull() {
        let json: [String: Any] = [
            "hook_event_name": "SubagentStop",
            "session_id": "sess-023",
            "agent_id": "agent-abc",
            "agent_type": "Explore",
            "agent_transcript_path": "/tmp/agent-abc.jsonl",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .subagentStopped(let info) = event else {
            Issue.record("Expected subagentStopped, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-023")
        #expect(info.agentId == "agent-abc")
        #expect(info.agentType == "Explore")
        #expect(info.agentTranscriptPath == "/tmp/agent-abc.jsonl")
    }

    @Test("SubagentStop maps minimal Claude payload correctly")
    func subagentStopClaudeMinimal() {
        let json: [String: Any] = [
            "hook_event_name": "SubagentStop",
            "session_id": "sess-024",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .subagentStopped(let info) = event else {
            Issue.record("Expected subagentStopped, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-024")
        #expect(info.agentId == nil)
        #expect(info.agentType == nil)
        #expect(info.agentTranscriptPath == nil)
    }

    // MARK: - Planning task snapshots

    @Test("Codex update_plan maps its ordered plan to a task-list snapshot")
    func codexUpdatePlan() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "codex-plan",
            "tool_name": "update_plan",
            "tool_input": [
                "explanation": "Starting implementation",
                "plan": [
                    ["step": "Inspect the event pipeline", "status": "completed"],
                    ["step": "Normalize plan events", "status": "in_progress"],
                    ["step": "Run tests", "status": "pending"],
                ],
            ],
        ]

        let event = ClaudeEventParser.parse(json)
        guard case .taskListReplaced(let info) = event else {
            Issue.record("Expected taskListReplaced, got \(event)")
            return
        }
        #expect(info.sessionId == "codex-plan")
        #expect(
            info.items.map(\.subject) == [
                "Inspect the event pipeline", "Normalize plan events", "Run tests",
            ])
        #expect(info.items.map(\.status) == [.completed, .inProgress, .pending])
    }

    @Test("Claude TodoWrite maps content and activeForm to the shared snapshot")
    func claudeTodoWrite() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "claude-todos",
            "tool_name": "TodoWrite",
            "tool_input": [
                "todos": [
                    [
                        "content": "Implement task tracking",
                        "activeForm": "Implementing task tracking",
                        "status": "in_progress",
                    ],
                    [
                        "content": "Verify the build",
                        "activeForm": "Verifying the build",
                        "status": "pending",
                    ],
                ]
            ],
        ]

        let event = ClaudeEventParser.parse(json)
        guard case .taskListReplaced(let info) = event else {
            Issue.record("Expected taskListReplaced, got \(event)")
            return
        }
        #expect(info.items.map(\.subject) == ["Implement task tracking", "Verify the build"])
        #expect(
            info.items.map(\.description) == [
                "Implementing task tracking", "Verifying the build",
            ])
        #expect(info.items.map(\.status) == [.inProgress, .pending])
    }

    @Test("A malformed plan remains a generic tool event instead of clearing known tasks")
    func malformedPlanFallsBackToToolEvent() {
        let event = ClaudeEventParser.parse([
            "hook_event_name": "PreToolUse",
            "session_id": "codex-plan",
            "tool_name": "update_plan",
            "tool_input": [
                "plan": [
                    ["step": "Valid", "status": "pending"],
                    ["step": "", "status": "completed"],
                ]
            ],
        ])

        guard case .toolStarted(let info) = event else {
            Issue.record("Expected generic toolStarted, got \(event)")
            return
        }
        #expect(info.toolName == "update_plan")
    }

    // MARK: - First-class TaskCreated / TaskCompleted

    @Test("TaskCreated (first-class hook) maps with taskId/assignee/teamName")
    func taskCreatedFirstClass() {
        let json: [String: Any] = [
            "hook_event_name": "TaskCreated",
            "session_id": "sess-030",
            "task_id": "task-1",
            "task_title": "Fix auth validation",
            "task_description": "Add input validation",
            "assigned_to": "researcher",
            "team_name": "alpha-team",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .taskCreated(let info) = event else {
            Issue.record("Expected taskCreated, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-030")
        #expect(info.taskId == "task-1")
        #expect(info.subject == "Fix auth validation")
        #expect(info.description == "Add input validation")
        #expect(info.assignee == "researcher")
        #expect(info.teamName == "alpha-team")
        #expect(info.source == .hook)
    }

    @Test("TaskCompleted (first-class hook) maps with taskId/completedBy/teamName")
    func taskCompletedFirstClass() {
        let json: [String: Any] = [
            "hook_event_name": "TaskCompleted",
            "session_id": "sess-030",
            "task_id": "task-1",
            "completed_by": "researcher",
            "completion_status": "success",
            "team_name": "alpha-team",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .taskCompleted(let info) = event else {
            Issue.record("Expected taskCompleted, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-030")
        #expect(info.taskId == "task-1")
        #expect(info.completedBy == "researcher")
        #expect(info.teamName == "alpha-team")
    }

    // MARK: - TeammateIdle

    @Test("TeammateIdle maps team_name/teammate_name/teammate_session_id")
    func teammateIdle() {
        let json: [String: Any] = [
            "hook_event_name": "TeammateIdle",
            "session_id": "sess-040",
            "team_name": "alpha-team",
            "teammate_name": "researcher",
            "teammate_session_id": "sess-041",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .teammateIdle(let info) = event else {
            Issue.record("Expected teammateIdle, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-040")
        #expect(info.teamName == "alpha-team")
        #expect(info.teammateName == "researcher")
        #expect(info.teammateSessionId == "sess-041")
    }
}
