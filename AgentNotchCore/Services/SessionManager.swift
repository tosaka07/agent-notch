import Combine
import Foundation

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [String: UnifiedSession] = [:]

    public init() {}

    public var activeSessions: [UnifiedSession] {
        sessions.values
            .filter { $0.status != .completed }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public var allSessions: [UnifiedSession] {
        sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    public var pendingPermissionCount: Int {
        sessions.values.reduce(0) { $0 + $1.pendingPermissions.count }
    }

    public func getOrCreateSession(id: String, agentType: AgentType) -> UnifiedSession {
        if let existing = sessions[id] {
            return existing
        }
        let session = UnifiedSession(id: id, agentType: agentType)
        sessions[id] = session
        return session
    }

    public func session(for id: String) -> UnifiedSession? {
        sessions[id]
    }

    public func removeSession(id: String) {
        sessions.removeValue(forKey: id)
    }

    public func removeAllSessions() {
        sessions.removeAll()
    }

    public func notifyChange() {
        objectWillChange.send()
    }
}
