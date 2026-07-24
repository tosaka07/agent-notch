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
        guard case let .sessionStarted(info) = event else {
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
        guard case let .toolStarted(info) = event else {
            Issue.record("Expected toolStarted")
            return
        }
        #expect(info.sessionId == "sess-001")
        #expect(info.toolName == "Edit")
        #expect(info.toolUseId == "tu-123")
        #expect(info.summary == "main.swift")
    }

    @Test("UserPromptSubmit maps to userPrompt with prompt field from payload")
    func userPromptSubmitWithPrompt() {
        let json: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "sess-003",
            "prompt": "Fix the auth bug",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case let .userPrompt(sessionId, prompt) = event else {
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
        guard case let .userPrompt(sessionId, prompt) = event else {
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
        guard case let .permissionRequested(info) = event else {
            Issue.record("Expected permissionRequested")
            return
        }
        #expect(info.sessionId == "sess-002")
        #expect(info.toolName == "Bash")
        #expect(info.toolInput["command"] == "rm -rf /tmp/test")
    }

    @Test("Stop maps to sessionIdle")
    func stop() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "sess-003",
        ]
        let event = ClaudeEventParser.parse(json)
        guard case let .sessionIdle(sessionId) = event else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(sessionId == "sess-003")
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

    // MARK: - permission_mode (共通フィールド)

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
        guard case let .permissionRequested(info) = event else {
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
        guard case let .taskCreated(info) = event else {
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
        guard case let .taskUpdated(sessionId, taskId, status) = event else {
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
        guard case let .subagentStarted(info) = event else {
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
        guard case let .subagentStarted(info) = event else {
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
        guard case let .subagentStarted(info) = event else {
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
        guard case let .subagentStopped(info) = event else {
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
        guard case let .subagentStopped(info) = event else {
            Issue.record("Expected subagentStopped, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-024")
        #expect(info.agentId == nil)
        #expect(info.agentType == nil)
        #expect(info.agentTranscriptPath == nil)
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
        guard case let .taskCreated(info) = event else {
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
        guard case let .taskCompleted(info) = event else {
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
        guard case let .teammateIdle(info) = event else {
            Issue.record("Expected teammateIdle, got \(event)")
            return
        }
        #expect(info.sessionId == "sess-040")
        #expect(info.teamName == "alpha-team")
        #expect(info.teammateName == "researcher")
        #expect(info.teammateSessionId == "sess-041")
    }
}
