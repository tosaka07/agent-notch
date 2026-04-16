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
        guard case let .taskCreated(sessionId, subject, description) = event else {
            Issue.record("Expected taskCreated, got \(event)")
            return
        }
        #expect(sessionId == "sess-010")
        #expect(subject == "Fix auth validation")
        #expect(description == "Add input validation to the auth module")
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
}
