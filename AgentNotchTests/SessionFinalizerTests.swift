import AgentNotchCore
import Foundation
import Testing

@testable import AgentNotch

@Suite("SessionFinalizer Tests")
@MainActor
struct SessionFinalizerTests {
    private final class NotificationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.withLock { count += 1 }
        }

        var value: Int {
            lock.withLock { count }
        }
    }

    @Test("finalize refuses to complete while a subagent is still running")
    func skipsWhileSubagentRuns() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "root", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "agent-a")
        session.status = .subagentRunning

        SessionFinalizer.finalize(sessionId: "root", manager: manager)

        #expect(session.status == .subagentRunning)
        #expect(session.runningSubagentCount == 1)
        #expect(session.doneAt == nil)
    }

    @Test("async completion output is suppressed after the session resumes")
    func suppressesStaleCompletionAfterResume() async throws {
        let manager = SessionManager()
        let sessionId = "resume-\(UUID().uuidString)"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .thinking
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .agentNotchSessionCompleted, object: nil, queue: nil
        ) { note in
            if note.object as? String == sessionId {
                counter.increment()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        SessionFinalizer.finalize(
            sessionId: sessionId, manager: manager,
            payloadLastMessage: "The turn is complete."
        )
        // The metrics task can land later. Once work resumes, that stale task must
        // not enqueue a completion notification or play its paired completion sound.
        session.status = .thinking
        try await Task.sleep(for: .milliseconds(100))

        #expect(counter.value == 0)
    }

    @Test("finalize is a no-op reentrancy guard when session is already done")
    func skipsWhenAlreadyDone() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        session.status = .thinking

        SessionFinalizer.finalize(sessionId: "s1", manager: manager)
        #expect(session.status == .done)
        let firstDoneAt = session.doneAt
        #expect(firstDoneAt != nil)

        // A duplicate finalization must leave the state — doneAt included — untouched
        // so the completion notification and sound do not fire twice.
        SessionFinalizer.finalize(sessionId: "s1", manager: manager)
        #expect(session.status == .done)
        #expect(session.doneAt == firstDoneAt)
    }
}
