import AgentNotchCore
import Foundation
import Testing
@testable import AgentNotch

@Suite("SessionFinalizer Tests")
@MainActor
struct SessionFinalizerTests {
    @Test("finalize is a no-op reentrancy guard when session is already done")
    func skipsWhenAlreadyDone() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        session.status = .thinking

        SessionFinalizer.finalize(sessionId: "s1", manager: manager)
        #expect(session.status == .done)
        let firstDoneAt = session.doneAt
        #expect(firstDoneAt != nil)

        // 2 回目の finalize（例: Stop の直後に TeammateIdle が重ねて飛んできたケース）は
        // 完了通知・サウンドを二重発火させないよう、doneAt を含めて状態を変更しない。
        SessionFinalizer.finalize(sessionId: "s1", manager: manager, completionSound: .subagentCompleted)
        #expect(session.status == .done)
        #expect(session.doneAt == firstDoneAt)
    }
}
