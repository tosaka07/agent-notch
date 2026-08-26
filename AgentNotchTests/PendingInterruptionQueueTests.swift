import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Pending interruption queue")
struct PendingInterruptionQueueTests {
    @Test("Permissions and questions keep one shared FIFO order")
    func preservesCrossKindArrivalOrder() {
        let start = Date(timeIntervalSince1970: 100)
        var queue = PendingInterruptionQueue()
        queue.enqueue(question(id: "q1", text: "First?", at: start))
        queue.enqueue(permission(id: "p1", at: start.addingTimeInterval(1)))
        queue.enqueue(question(id: "q2", text: "Third?", at: start.addingTimeInterval(2)))

        #expect(queue.items.map(\.id) == ["question:q1", "permission:p1", "question:q2"])
        #expect(queue.first?.id == "question:q1")

        queue.remove(kind: .question, toolUseId: "q1")
        #expect(queue.first?.id == "permission:p1")

        queue.remove(kind: .permission, toolUseId: "p1")
        #expect(queue.first?.id == "question:q2")
    }

    @Test("Claude's duplicate hook observation replaces in place without jumping the queue")
    func coalescesDuplicateClaudeTransportObservation() {
        let start = Date(timeIntervalSince1970: 100)
        var queue = PendingInterruptionQueue()
        queue.enqueue(question(id: "pre-tool", text: "Same?", at: start))
        queue.enqueue(permission(id: "later", at: start.addingTimeInterval(1)))

        let inserted = queue.enqueue(
            question(id: "permission-hook", text: "Same?", at: start.addingTimeInterval(2)),
            coalesceMatchingContent: true
        )

        #expect(!inserted)
        #expect(queue.items.map(\.id) == ["question:permission-hook", "permission:later"])
        #expect(queue.first?.receivedAt == start)
        #expect(queue.question(toolUseId: "pre-tool")?.toolUseId == "permission-hook")

        queue.remove(kind: .question, toolUseId: "pre-tool")
        #expect(queue.first?.id == "permission:later")
    }

    @Test("A repeated observation cannot replace the response-channel identity")
    func repeatedObservationKeepsResponseChannelIdentity() {
        let start = Date(timeIntervalSince1970: 100)
        var queue = PendingInterruptionQueue()
        queue.enqueue(question(id: "pre-tool", text: "Same?", at: start))
        queue.enqueue(
            question(id: "permission-hook", text: "Same?", at: start.addingTimeInterval(1)),
            coalesceMatchingContent: true
        )

        queue.enqueue(
            question(id: "pre-tool", text: "Same?", at: start.addingTimeInterval(2))
        )

        #expect(queue.first?.id == "question:permission-hook")
        #expect(queue.question(toolUseId: "pre-tool")?.toolUseId == "permission-hook")
    }

    @Test("Separate observations with identical text remain separate")
    func identicalObservationsRemainSeparate() {
        let start = Date(timeIntervalSince1970: 100)
        var queue = PendingInterruptionQueue()

        queue.enqueue(question(id: "first", text: "Proceed?", at: start))
        queue.enqueue(
            question(id: "second", text: "Proceed?", at: start.addingTimeInterval(1))
        )

        #expect(queue.items.map(\.id) == ["question:first", "question:second"])
    }

    @Test("Updating and removing a hidden item does not disturb the visible head")
    func hiddenItemMutationKeepsHead() {
        let start = Date(timeIntervalSince1970: 100)
        var queue = PendingInterruptionQueue()
        queue.enqueue(question(id: "visible", text: "First?", at: start))
        queue.enqueue(
            question(id: "hidden", text: "Second?", at: start.addingTimeInterval(1))
        )

        queue.updateQuestion(toolUseId: "hidden") { $0.isExpired = true }
        #expect(queue.first?.id == "question:visible")
        #expect(queue.question(toolUseId: "hidden")?.isExpired == true)

        queue.remove(kind: .question, toolUseId: "hidden")
        #expect(queue.items.map(\.id) == ["question:visible"])
    }

    @Test("Replacing the compatibility question keeps its shared queue position")
    func compatibilityQuestionReplacementPreservesPosition() {
        let session = UnifiedSession(id: "session", agentType: .claudeCode)
        session.pendingQuestion = question(id: "first", text: "First?", at: .now)
        session.pendingPermissions = [permission(id: "permission", at: .now)]

        session.pendingQuestion = question(id: "replacement", text: "Updated?", at: .now)

        #expect(
            session.pendingInterruptions.items.map(\.id)
                == ["question:replacement", "permission:permission"]
        )
    }

    @Test("Replacing compatibility permissions keeps their shared queue positions")
    func compatibilityPermissionReplacementPreservesPosition() {
        let session = UnifiedSession(id: "session", agentType: .claudeCode)
        session.pendingPermissions = [permission(id: "first", at: .now)]
        session.pendingQuestion = question(id: "question", text: "Later?", at: .now)

        session.pendingPermissions = [permission(id: "replacement", at: .now)]

        #expect(
            session.pendingInterruptions.items.map(\.id)
                == ["permission:replacement", "question:question"]
        )
    }

    @Test("Compatibility question replacement preserves arrival and correlation metadata")
    func compatibilityQuestionReplacementPreservesMetadata() throws {
        let receivedAt = Date(timeIntervalSince1970: 100)
        let session = UnifiedSession(id: "session", agentType: .claudeCode)
        session.pendingQuestion = PendingQuestion(
            toolUseId: "observation",
            questions: [],
            correlationToolUseIds: ["observation", "response-channel"],
            receivedAt: receivedAt
        )

        session.pendingQuestion = question(id: "replacement", text: "Updated?", at: .now)

        let replacement = try #require(session.pendingQuestion)
        #expect(replacement.receivedAt == receivedAt)
        #expect(
            replacement.correlationToolUseIds
                == ["observation", "response-channel", "replacement"]
        )

        session.pendingQuestion = nil
        #expect(session.pendingInterruptions.isEmpty)
    }

    private func question(id: String, text: String, at date: Date) -> PendingQuestion {
        PendingQuestion(
            toolUseId: id,
            questions: [
                AskQuestionInfo.Question(
                    question: text,
                    header: nil,
                    multiSelect: false,
                    options: [],
                    allowsOther: true
                )
            ],
            receivedAt: date
        )
    }

    private func permission(id: String, at date: Date) -> PermissionRequest {
        PermissionRequest(
            id: id,
            agentType: .claudeCode,
            sessionId: "session",
            toolName: "Bash",
            toolInput: [:],
            toolUseId: id,
            timestamp: date,
            canRespond: true
        )
    }
}
