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

    public struct SweptSession: Sendable {
        public let id: String
        public let projectName: String
        public let reason: SweptReason
    }

    public enum SweptReason: Sendable {
        case directoryDeleted
        case timeout
    }

    /// Remove sessions that are stale. Returns info about removed sessions.
    @discardableResult
    public func sweepStale(timeoutSeconds: Int) -> [SweptSession] {
        let now = Date()
        var swept: [SweptSession] = []

        for (id, session) in sessions {
            if session.status.isRunning || session.status == .permissionWaiting {
                continue
            }

            let name = session.originRepoName
                ?? (session.cwd as NSString?)?.lastPathComponent ?? "Session"

            if let cwd = session.cwd, !FileManager.default.fileExists(atPath: cwd) {
                swept.append(SweptSession(id: id, projectName: name, reason: .directoryDeleted))
                sessions.removeValue(forKey: id)
                continue
            }

            if timeoutSeconds > 0 {
                let elapsed = now.timeIntervalSince(session.lastActivityAt)
                if elapsed > TimeInterval(timeoutSeconds) {
                    swept.append(SweptSession(id: id, projectName: name, reason: .timeout))
                    sessions.removeValue(forKey: id)
                }
            }
        }

        if !swept.isEmpty {
            notifyChange()
        }
        return swept
    }
}
