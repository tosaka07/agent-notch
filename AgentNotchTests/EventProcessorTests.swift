import AgentNotchCore
import Foundation
import Testing
@testable import AgentNotch

/// issue #19: subagent 内での PermissionRequest 承認が一覧カードに反映されない問題の回帰テスト。
@Suite("EventProcessor status guard tests (#19)")
@MainActor
struct EventProcessorTests {
    @Test("permissionWaiting survives a concurrent (different tool) PreToolUse/PostToolUse")
    func permissionWaitingSurvivesConcurrentToolEvent() {
        let manager = SessionManager()
        let sessionId = "s1"

        let subagentStart = ClaudeEventParser.parse([
            "hook_event_name": "SubagentStart",
            "session_id": sessionId,
            "agent_type": "explorer",
            "agent_id": "agent-a",
        ])
        EventProcessor.apply(subagentStart, agentType: .claudeCode, manager: manager)
        let session = manager.session(for: sessionId)!
        #expect(session.status == .subagentRunning)

        // 別の subagent のツールが承認を要求 → permissionWaiting に遷移
        let permissionRequest = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "Bash",
            "tool_use_id": "tool-1",
            "tool_input": ["command": "rm -rf foo"],
        ])
        EventProcessor.apply(permissionRequest, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
        #expect(session.pendingPermissions.count == 1)

        // 承認待ちの間に、別 tool_use_id の PreToolUse/PostToolUse が同じセッションに届いても
        // permissionWaiting のバッジを消してはいけない。
        let otherToolStart = ClaudeEventParser.parse([
            "hook_event_name": "PreToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
            "tool_input": ["file_path": "/tmp/x"],
        ])
        EventProcessor.apply(otherToolStart, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)

        let otherToolEnd = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
        ])
        EventProcessor.apply(otherToolEnd, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
    }

    @Test("idle_prompt notification does not clear permissionWaiting")
    func idlePromptDoesNotClearPermissionWaiting() {
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: sessionId, toolName: "Bash",
                toolInput: [:], toolUseId: "tool-1", timestamp: Date(), canRespond: true
            ),
        ]

        let idlePrompt = ClaudeEventParser.parse([
            "hook_event_name": "Notification",
            "session_id": sessionId,
            "type": "idle_prompt",
            "message": "",
        ])
        EventProcessor.apply(idlePrompt, agentType: .claudeCode, manager: manager)

        #expect(session.status == .permissionWaiting)
    }

    @Test("PreCompact does not clear permissionWaiting (symmetry with PostCompact)")
    func preCompactDoesNotClearPermissionWaiting() {
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: sessionId, toolName: "Bash",
                toolInput: [:], toolUseId: "tool-1", timestamp: Date(), canRespond: true
            ),
        ]

        let preCompact = ClaudeEventParser.parse([
            "hook_event_name": "PreCompact",
            "session_id": sessionId,
        ])
        EventProcessor.apply(preCompact, agentType: .claudeCode, manager: manager)

        #expect(session.status == .permissionWaiting)
    }

    @Test("UserPromptSubmit does not clear permissionWaiting")
    func userPromptDoesNotClearPermissionWaiting() {
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: sessionId, toolName: "Bash",
                toolInput: [:], toolUseId: "tool-1", timestamp: Date(), canRespond: true
            ),
        ]

        let userPrompt = ClaudeEventParser.parse([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "prompt": "続けて",
        ])
        EventProcessor.apply(userPrompt, agentType: .claudeCode, manager: manager)

        #expect(session.status == .permissionWaiting)
    }

    @Test("permissionWaiting from a pending AskUserQuestion also survives a concurrent tool event")
    func pendingQuestionSurvivesConcurrentToolEvent() {
        let manager = SessionManager()
        let sessionId = "s1"

        let subagentStart = ClaudeEventParser.parse([
            "hook_event_name": "SubagentStart",
            "session_id": sessionId,
            "agent_type": "explorer",
            "agent_id": "agent-a",
        ])
        EventProcessor.apply(subagentStart, agentType: .claudeCode, manager: manager)
        let session = manager.session(for: sessionId)!
        #expect(session.status == .subagentRunning)

        // 別の subagent が AskUserQuestion（PermissionRequest 経由）で回答待ちに遷移
        let askQuestion = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "AskUserQuestion",
            "tool_use_id": "tool-q1",
            "tool_input": [
                "questions": [
                    ["question": "どちらの方針にしますか？", "options": [["label": "A"], ["label": "B"]]],
                ],
            ],
        ])
        EventProcessor.apply(askQuestion, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
        #expect(session.pendingQuestion != nil)

        // 回答待ちの間に、別 subagent の PreToolUse/PostToolUse が届いてもバッジを消してはいけない。
        let otherToolStart = ClaudeEventParser.parse([
            "hook_event_name": "PreToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
            "tool_input": ["file_path": "/tmp/x"],
        ])
        EventProcessor.apply(otherToolStart, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)

        let otherToolEnd = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
        ])
        EventProcessor.apply(otherToolEnd, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
    }
}
