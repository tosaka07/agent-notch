import Foundation
import Testing

@testable import AgentNotchCore

/// Tests for `statusAfterPermissionResolved()`, which decides the status to return
/// to after an approval, denial, or answer.
@Suite("UnifiedSession statusAfterPermissionResolved tests")
struct UnifiedSessionTests {
    @Test("returns .thinking when nothing else is pending and no subagent is running")
    func plainThinking() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        #expect(session.statusAfterPermissionResolved() == .thinking)
    }

    @Test("returns .subagentRunning when a subagent is still running after clearing the permission")
    func restoresSubagentRunning() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "explorer", agentId: "agent-a")
        #expect(session.runningSubagentCount == 1)

        #expect(session.statusAfterPermissionResolved() == .subagentRunning)
    }

    @Test("returns .permissionWaiting when another permission request is still pending")
    func keepsPermissionWaitingWhenMoreArePending() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: "s1", toolName: "Bash",
                toolInput: [:], toolUseId: "tool-2", timestamp: Date(), canRespond: true
            )
        ]
        #expect(session.statusAfterPermissionResolved() == .permissionWaiting)
    }

    @Test("returns .permissionWaiting when a question is still pending")
    func keepsPermissionWaitingWhenQuestionPending() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.pendingQuestion = PendingQuestion(toolUseId: "tool-1", questions: [])
        #expect(session.statusAfterPermissionResolved() == .permissionWaiting)
    }
}
