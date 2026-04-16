import AgentNotchCore
import Foundation
import Testing
@testable import AgentNotch

@Suite("CompactPageView.primarySession")
@MainActor
struct CompactPrimarySessionTests {
    @Test("empty returns nil")
    func empty() {
        #expect(CompactPageView.primarySession([]) == nil)
    }

    @Test("urgency rank decides winner")
    func urgency() {
        let s1 = makeSession(id: "a", status: .thinking, at: Date())
        let s2 = makeSession(id: "b", status: .permissionWaiting, at: Date())
        let s3 = makeSession(id: "c", status: .toolRunning, at: Date())
        #expect(CompactPageView.primarySession([s1, s2, s3])?.id == "b")
    }

    @Test("tie on urgency breaks by most recent lastActivityAt")
    func recencyTiebreak() {
        let older = makeSession(id: "old", status: .toolRunning, at: Date(timeIntervalSinceNow: -60))
        let newer = makeSession(id: "new", status: .toolRunning, at: Date())
        #expect(CompactPageView.primarySession([older, newer])?.id == "new")
    }

    // MARK: - Helpers

    private func makeSession(id: String, status: SessionStatus, at activity: Date) -> UnifiedSession {
        let session = UnifiedSession(id: id, agentType: .claudeCode, status: status)
        session.lastActivityAt = activity
        return session
    }
}
