import Combine
import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var sessions: [String: UnifiedSession] = [:]

    var activeSessions: [UnifiedSession] {
        sessions.values
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
        return session
    }

    func session(for id: String) -> UnifiedSession? {
        sessions[id]
    }

    /// Call after mutating any session property to trigger SwiftUI update
    func notifyChange() {
        objectWillChange.send()
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
