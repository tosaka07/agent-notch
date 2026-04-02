import Foundation
import Testing
@testable import AgentNotch

@Suite("SessionManager Tests")
@MainActor
struct SessionManagerTests {
    @Test("Creates new session")
    func createsNewSession() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        #expect(session.id == "s1")
        #expect(session.agentType == .claudeCode)
        #expect(session.status == .starting)
        #expect(manager.allSessions.count == 1)
    }

    @Test("Returns existing session for same id")
    func returnsExistingSession() {
        let manager = SessionManager()
        let first = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        first.status = .thinking
        let second = manager.getOrCreateSession(id: "s1", agentType: .codex)
        #expect(second.status == .thinking)
        #expect(second.agentType == .claudeCode)
        #expect(manager.allSessions.count == 1)
    }

    @Test("Removes session by id")
    func removesSession() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        manager.removeSession(id: "s1")
        #expect(manager.allSessions.isEmpty)
    }

    @Test("Removes all sessions")
    func removesAllSessions() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        _ = manager.getOrCreateSession(id: "s2", agentType: .codex)
        manager.removeAllSessions()
        #expect(manager.allSessions.isEmpty)
    }

    @Test("Tracks multiple sessions and filters active")
    func tracksMultipleSessions() {
        let manager = SessionManager()
        let s1 = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        s1.status = .thinking

        let s2 = manager.getOrCreateSession(id: "s2", agentType: .codex)
        s2.status = .completed

        let s3 = manager.getOrCreateSession(id: "s3", agentType: .geminiCLI)
        s3.status = .toolRunning

        #expect(manager.allSessions.count == 3)
        #expect(manager.activeSessions.count == 2)
    }

    @Test("session(for:) returns nil for unknown id")
    func sessionForUnknownId() {
        let manager = SessionManager()
        #expect(manager.session(for: "nonexistent") == nil)
    }
}
