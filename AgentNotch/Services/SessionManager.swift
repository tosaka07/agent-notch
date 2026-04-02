import Foundation

@Observable
@MainActor
final class SessionManager {
    private(set) var sessions: [String: UnifiedSession] = [:]

    /// Incremented on every mutation to force SwiftUI re-evaluation
    var changeCount: Int = 0

    var activeSessions: [UnifiedSession] {
        // Access changeCount so @Observable tracks it
        _ = changeCount
        return sessions.values
            .filter { $0.status != .completed }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var allSessions: [UnifiedSession] {
        sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    var pendingPermissionCount: Int {
        sessions.values.reduce(0) { $0 + $1.pendingPermissions.count }
    }

    func getOrCreateSession(id: String, agentType: AgentType) -> UnifiedSession {
        if let existing = sessions[id] {
            return existing
        }
        let session = UnifiedSession(id: id, agentType: agentType)
        sessions[id] = session
        changeCount += 1
        return session
    }

    func session(for id: String) -> UnifiedSession? {
        sessions[id]
    }

    func cleanupCompleted(olderThan cutoff: Date) {
        let keysToRemove = sessions.filter { _, session in
            session.status == .completed &&
            session.endedAt != nil &&
            session.endedAt! < cutoff
        }.map(\.key)

        for key in keysToRemove {
            sessions.removeValue(forKey: key)
        }
    }
}
