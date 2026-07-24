import Combine
import Foundation

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [String: UnifiedSession] = [:]
    /// ユーザーが付与したセッション状態（pin / mute / markedDoneAt）。
    /// `sessions` と同じ id をキーにする。session 削除時に同時削除。
    @Published public private(set) var userStates: [String: SessionUserState] = [:]

    /// `userStates` が変化した時に呼ばれる hook。永続化を GUI 側で行うために使う。
    /// Core は Defaults に依存しないため、保存ロジックは GUI 側で差し込む。
    /// 変化の詳細は `userStates` 全体を読み取る前提（頻繁な I/O を避けたい場合は呼び出し側で debounce）。
    public var onUserStateChange: (@MainActor () -> Void)?

    public init() {}

    /// 外部（Defaults 復元など）から userStates を一括初期化する。
    public func restoreUserStates(_ states: [String: SessionUserState]) {
        userStates = states
        notifyChange()
    }

    public func userState(for id: String) -> SessionUserState {
        userStates[id] ?? .empty
    }

    /// セッションが mute されているか。EventProcessor / SessionFinalizer の gating に使う。
    public func isMuted(_ id: String) -> Bool {
        userStates[id]?.muted ?? false
    }

    public func setPinned(_ id: String, _ value: Bool) {
        updateUserState(id) { $0.pinned = value }
    }

    public func setMuted(_ id: String, _ value: Bool) {
        updateUserState(id) { $0.muted = value }
    }

    /// `markedDoneAt` を「今」に設定。ソート時に下に沈み、opacity 表示になる。
    public func markDone(_ id: String, at date: Date = Date()) {
        updateUserState(id) { $0.markedDoneAt = date }
    }

    /// `markedDoneAt` をクリア。Reopen 操作。
    public func unmarkDone(_ id: String) {
        updateUserState(id) { $0.markedDoneAt = nil }
    }

    private func updateUserState(_ id: String, _ mutate: (inout SessionUserState) -> Void) {
        let old = userStates[id] ?? .empty
        var state = old
        mutate(&state)
        guard state != old else { return }

        if state.isDefault {
            userStates.removeValue(forKey: id)
        } else {
            userStates[id] = state
        }
        onUserStateChange?()
        notifyChange()
    }

    public var activeSessions: [UnifiedSession] {
        sessions.values
            .filter { $0.status != .completed }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public var allSessions: [UnifiedSession] {
        sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    /// 指定のソート軸で並べた active なセッション一覧。
    /// - pinned されたセッションは常に先頭に集められる（pinned 内部でも `order` が適用される）。
    /// - `userStates` は SessionManager 自身の状態を利用する。
    public func sortedSessions(order: SessionSortOrder) -> [UnifiedSession] {
        let sessions = self.sessions.values.filter { $0.status != .completed }
        return Self.sort(sessions: Array(sessions), order: order, userStates: userStates)
    }

    /// 指定のソート軸・グループ軸で active なセッションをグループ化して返す。
    /// 結果は表示順に並んだ `[SessionGroup]`。`grouping == .none` の場合は 1 つのグループを返す。
    public func groupedSessions(
        order: SessionSortOrder,
        grouping: SessionGrouping
    ) -> [SessionGroup] {
        let sorted = sortedSessions(order: order)

        if grouping == .none {
            return [SessionGroup(key: "__all__", title: "", sessions: sorted)]
        }

        var buckets: [(key: String, title: String, items: [UnifiedSession])] = []
        var index: [String: Int] = [:]

        for session in sorted {
            let (key, title) = Self.groupKey(for: session, grouping: grouping)
            if let i = index[key] {
                buckets[i].items.append(session)
            } else {
                index[key] = buckets.count
                buckets.append((key, title, [session]))
            }
        }

        // グループ自体の並び順: status は urgencyRank 昇順、それ以外は最初のアイテムの順序を維持
        if grouping == .status {
            buckets.sort { lhs, rhs in
                (lhs.items.first?.status.urgencyRank ?? Int.max)
                    < (rhs.items.first?.status.urgencyRank ?? Int.max)
            }
        }

        // team グループ内はリーダー（teammateName == nil）を先頭に並べる。
        if grouping == .team {
            buckets = buckets.map { bucket in
                let leaders = bucket.items.filter { $0.teammateName == nil }
                let members = bucket.items.filter { $0.teammateName != nil }
                return (bucket.key, bucket.title, leaders + members)
            }
        }

        return buckets.map { SessionGroup(key: $0.key, title: $0.title, sessions: $0.items) }
    }

    private static func sort(
        sessions: [UnifiedSession],
        order: SessionSortOrder,
        userStates: [String: SessionUserState]
    ) -> [UnifiedSession] {
        sessions.sorted { lhs, rhs in
            // Pinned は常に先頭
            let lPinned = userStates[lhs.id]?.pinned ?? false
            let rPinned = userStates[rhs.id]?.pinned ?? false
            if lPinned != rPinned { return lPinned }

            // isUserDone な session はソート軸に関係なく下に沈める
            let lDone = isUserDone(lhs, userStates: userStates)
            let rDone = isUserDone(rhs, userStates: userStates)
            if lDone != rDone { return !lDone }

            switch order {
            case .urgency:
                if lhs.status.urgencyRank != rhs.status.urgencyRank {
                    return lhs.status.urgencyRank < rhs.status.urgencyRank
                }
                return lhs.lastActivityAt > rhs.lastActivityAt
            case .latestActivity:
                return lhs.lastActivityAt > rhs.lastActivityAt
            case .startedAt:
                return lhs.startedAt > rhs.startedAt
            case .project:
                let lName = projectDisplayName(for: lhs).lowercased()
                let rName = projectDisplayName(for: rhs).lowercased()
                if lName != rName { return lName < rName }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
        }
    }

    private static func groupKey(
        for session: UnifiedSession,
        grouping: SessionGrouping
    ) -> (key: String, title: String) {
        switch grouping {
        case .none:
            return ("__all__", "")
        case .status:
            return (session.status.rawValue, session.status.label)
        case .project:
            let name = projectDisplayName(for: session)
            return (name, name)
        case .agent:
            return (session.agentType.rawValue, session.agentType.displayName)
        case .team:
            let name = session.teamName ?? "__solo__"
            let title = session.teamName ?? "NO TEAM"
            return (name, title)
        }
    }

    private static func projectDisplayName(for session: UnifiedSession) -> String {
        if let origin = session.originRepoName, !origin.isEmpty { return origin }
        if let cwd = session.cwd, !cwd.isEmpty {
            return (cwd as NSString).lastPathComponent
        }
        return "No Project"
    }

    /// ユーザーが mark done したかつそれ以降 activity が無い状態。
    public static func isUserDone(
        _ session: UnifiedSession,
        userStates: [String: SessionUserState]
    ) -> Bool {
        guard let markedAt = userStates[session.id]?.markedDoneAt else { return false }
        return session.lastActivityAt <= markedAt
    }

    public func isUserDone(_ session: UnifiedSession) -> Bool {
        Self.isUserDone(session, userStates: userStates)
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

    /// 指定 teamName に所属する（active/completed 問わない）全セッション。team ボードの読み取りに使う。
    public func teamSessions(name: String) -> [UnifiedSession] {
        sessions.values.filter { $0.teamName == name }
    }

    public func removeSession(id: String) {
        sessions.removeValue(forKey: id)
        if userStates.removeValue(forKey: id) != nil {
            onUserStateChange?()
        }
    }

    public func removeAllSessions() {
        let hadUserStates = !userStates.isEmpty
        sessions.removeAll()
        userStates.removeAll()
        if hadUserStates {
            onUserStateChange?()
        }
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
