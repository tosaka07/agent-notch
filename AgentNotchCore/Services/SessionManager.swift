import Combine
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [String: UnifiedSession] = [:]
    /// User-assigned session state (pin / mute / title display / markedDoneAt), keyed by the same
    /// id as `sessions` and removed together with the session.
    @Published public private(set) var userStates: [String: SessionUserState] = [:]

    /// Called whenever `userStates` changes, so the GUI can persist it. Core does not depend on
    /// Defaults, so the saving logic is injected from the GUI side.
    /// The callback carries no diff; read all of `userStates`. Debounce on the caller's side to
    /// avoid frequent I/O.
    public var onUserStateChange: (@MainActor () -> Void)?

    /// Called after session-visible state changes. The GUI uses this as the single persistence
    /// seam instead of teaching every event handler about files or serialization.
    public var onSessionChange: (@MainActor () -> Void)?

    /// PIDs replaced by a newer runtime for the same logical session during this app process.
    /// Late hook messages from these processes must not roll the card back to an older runtime.
    private var retiredRuntimePIDs: [String: Set<Int32>] = [:]

    public init() {}

    /// Bulk-initializes userStates from outside (e.g. restoring from Defaults).
    public func restoreUserStates(_ states: [String: SessionUserState]) {
        userStates = states
        notifyChange()
    }

    public func userState(for id: String) -> SessionUserState {
        userStates[id] ?? .empty
    }

    /// Whether the session is muted. Used to gate EventProcessor and SessionFinalizer.
    public func isMuted(_ id: String) -> Bool {
        userStates[id]?.muted ?? false
    }

    public func setPinned(_ id: String, _ value: Bool) {
        updateUserState(id) { $0.pinned = value }
    }

    public func setMuted(_ id: String, _ value: Bool) {
        updateUserState(id) { $0.muted = value }
    }

    /// Chooses whether this card uses the agent's session title or the latest user prompt.
    /// The value is carried through the existing per-session persistence seam.
    public func setTitleDisplayPreference(
        _ id: String,
        _ preference: SessionTitleDisplayPreference
    ) {
        updateUserState(id) { $0.titleDisplayPreference = preference }
    }

    /// Whether every session currently shown in the active-session list is muted.
    ///
    /// An empty list is not considered muted, which keeps the aggregate toggle in its off state
    /// until there is something it can affect.
    public var areAllActiveSessionsMuted: Bool {
        let activeIDs = sessions.values
            .filter { $0.status != .completed }
            .map(\.id)
        return !activeIDs.isEmpty && activeIDs.allSatisfy(isMuted)
    }

    /// Applies one mute state to every session currently shown in the active-session list.
    ///
    /// This is intentionally a bulk mutation rather than repeated `setMuted` calls so persistence
    /// and view updates fire once even when many sessions are on screen.
    public func setAllActiveSessionsMuted(_ value: Bool) {
        let activeIDs = sessions.values
            .filter { $0.status != .completed }
            .map(\.id)
        guard !activeIDs.isEmpty else { return }

        var didChange = false
        for id in activeIDs {
            var state = userStates[id] ?? .empty
            guard state.muted != value else { continue }
            state.muted = value
            if state.isDefault {
                userStates.removeValue(forKey: id)
            } else {
                userStates[id] = state
            }
            didChange = true
        }

        guard didChange else { return }
        onUserStateChange?()
        notifyChange()
    }

    /// Sets `markedDoneAt` to now, which sinks the session in the sort order and dims it.
    public func markDone(_ id: String, at date: Date = Date()) {
        updateUserState(id) { $0.markedDoneAt = date }
    }

    /// Clears `markedDoneAt`; the reopen action.
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

    /// The session owning the oldest currently reachable interruption.
    ///
    /// Only each session's queue head can be shown. Taking the oldest head across sessions is
    /// therefore equivalent to one global FIFO while keeping the storage local to its session.
    public func nextPendingInterruptionSession() -> UnifiedSession? {
        sessions.values
            .compactMap { session -> (UnifiedSession, PendingInterruption)? in
                guard let interruption = session.currentInterruption else { return nil }
                return (session, interruption)
            }
            .min { lhs, rhs in
                if lhs.1.receivedAt != rhs.1.receivedAt {
                    return lhs.1.receivedAt < rhs.1.receivedAt
                }
                if lhs.0.startedAt != rhs.0.startedAt {
                    return lhs.0.startedAt < rhs.0.startedAt
                }
                return lhs.0.id < rhs.0.id
            }?
            .0
    }

    /// Active sessions sorted by the given axis.
    /// - Pinned sessions are always gathered at the top, with `order` still applied among them.
    /// - Uses SessionManager's own `userStates`.
    public func sortedSessions(order: SessionSortOrder) -> [UnifiedSession] {
        let sessions = self.sessions.values.filter { $0.status != .completed }
        return Self.sort(sessions: Array(sessions), order: order, userStates: userStates)
    }

    /// Groups the active sessions by the given sort and grouping axes.
    /// Returns `[SessionGroup]` in display order; a single group when `grouping == .none`.
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

        // Order of the groups themselves: ascending urgencyRank for status, otherwise the order the first items came in.
        if grouping == .status {
            buckets.sort { lhs, rhs in
                (lhs.items.first?.status.urgencyRank ?? Int.max)
                    < (rhs.items.first?.status.urgencyRank ?? Int.max)
            }
        }

        // Within a team group, leaders (teammateName == nil) come first.
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
            // Pinned always comes first.
            let lPinned = userStates[lhs.id]?.pinned ?? false
            let rPinned = userStates[rhs.id]?.pinned ?? false
            if lPinned != rPinned { return lPinned }

            // Sessions marked done by the user sink to the bottom regardless of the sort axis.
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

    /// The user marked it done and no activity has happened since.
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

    /// The durable representation consumed by the GUI's file adapter.
    public var sessionSnapshots: [SessionSnapshot] {
        sessions.values
            .filter { $0.status != .completed }
            .map(SessionSnapshot.init(session:))
            .sorted { $0.id < $1.id }
    }

    /// Restores non-actionable sessions before the live socket starts.
    public func restoreSessions(from snapshots: [SessionSnapshot]) {
        var restored: [String: UnifiedSession] = [:]
        for snapshot in snapshots where snapshot.lastKnownStatus != .completed {
            restored[snapshot.id] = snapshot.makeRestoredSession()
        }
        sessions = restored
        retiredRuntimePIDs.removeAll()
        notifyChange()
    }

    /// Registers an incoming hook event against the currently attached runtime.
    ///
    /// Session ID is the logical identity; PID is replaceable runtime metadata. A restored or
    /// inactive session accepts the first fresh event from any PID. Once live, a different PID
    /// may take over only through SessionStart. PIDs replaced in this app process are retired so
    /// their delayed events cannot roll state back.
    @discardableResult
    public func prepareForRuntimeEvent(
        sessionId: String,
        agentType: AgentType,
        pid: Int32?,
        isSessionStart: Bool,
        at now: Date = Date()
    ) -> Bool {
        guard !sessionId.isEmpty else { return false }
        guard let session = sessions[sessionId] else {
            // The event processor creates recognized new sessions. Do not create cards for
            // unknown events merely because a message reached the socket.
            return true
        }
        guard session.agentType == agentType else { return false }

        if let pid, retiredRuntimePIDs[sessionId]?.contains(pid) == true {
            return false
        }

        if session.presence != .live {
            attachRuntime(session, pid: pid, at: now)
            return true
        }

        if isSessionStart {
            attachRuntime(session, pid: pid, at: now)
            return true
        }

        if let currentPID = session.pid, let pid, currentPID != pid {
            return false
        }

        if session.pid == nil, let pid {
            session.pid = pid
            session.lastResumedAt = now
        }
        return true
    }

    private func attachRuntime(_ session: UnifiedSession, pid: Int32?, at now: Date) {
        if let oldPID = session.pid, oldPID != pid {
            retiredRuntimePIDs[session.id, default: []].insert(oldPID)
        }

        session.presence = .live
        session.lastKnownStatus = nil
        session.status = .idle
        session.endedAt = nil
        session.doneAt = nil
        session.lastResumedAt = now
        session.currentTool = nil
        session.pendingInterruptions.removeAll()
        session.foldRunningSubagentsToCompleted(at: now)
        session.subagentCountAtCompletion = 0

        let runtimeChanged = session.pid != pid
        session.pid = pid
        if runtimeChanged {
            session.tty = nil
            session.terminalAppName = nil
            session.terminalAppIcon = nil
            session.tmuxPaneTarget = nil
            session.terminalInfoResolved = false
        }
    }

    /// Finds an existing session with the same pid and the same cwd, excluding `excludedId`.
    ///
    /// cwd is part of the match for safety: any process belonging to the same user can write to the
    /// socket, so matching on pid alone would let a forged SessionStart carrying a `_pid` (a value
    /// anyone can enumerate with `ps`) merge away someone else's running session. Requiring the cwd
    /// too means an attacker who does not know it cannot delete an unrelated session.
    /// A nil cwd on either side never counts as a match.
    public func session(withPid pid: Int32, cwd: String?, excluding excludedId: String) -> UnifiedSession? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return sessions.values.first { $0.pid == pid && $0.cwd == cwd && $0.id != excludedId }
    }

    /// The `SessionInfo.source` values for which `reconcileSessionStart` may merge an old session,
    /// i.e. only those meaning "the same conversation continuing in the same process".
    /// `startup` is excluded: an agent-teams teammate can start as a new session inside the same
    /// process and share the parent's pid, so including `startup` would delete the leader session.
    private static let reconcilableSources: Set<String> = ["resume", "clear", "compact"]

    /// Merges the old session into the new one when Claude Code issues a fresh session_id within
    /// the same process, as `/compact`, `/clear`, and `resume` do — otherwise the list splits in two.
    /// If an existing session with the same pid and cwd is found, its pin/mute state is carried over
    /// to the new id and the old session is removed. When `source` is none of `resume`, `clear`, or
    /// `compact` (including `startup`), nothing happens, since it may be a different process or a
    /// different conversation. Old sessions whose process died are collected separately by
    /// `sweepStale`'s liveness check.
    @discardableResult
    public func reconcileSessionStart(newId: String, pid: Int32?, cwd: String?, source: String?) -> Bool {
        guard let source, Self.reconcilableSources.contains(source) else { return false }
        guard let pid, let old = session(withPid: pid, cwd: cwd, excluding: newId) else { return false }

        if let state = userStates[old.id], !state.isDefault {
            userStates[newId] = state
        }
        removeSession(id: old.id)
        return true
    }

    /// Every session belonging to the given teamName, active or completed. Used to read the team board.
    public func teamSessions(name: String) -> [UnifiedSession] {
        sessions.values.filter { $0.teamName == name }
    }

    public func removeSession(id: String) {
        sessions.removeValue(forKey: id)
        retiredRuntimePIDs.removeValue(forKey: id)
        if userStates.removeValue(forKey: id) != nil {
            onUserStateChange?()
        }
    }

    public func removeAllSessions() {
        let hadUserStates = !userStates.isEmpty
        sessions.removeAll()
        retiredRuntimePIDs.removeAll()
        userStates.removeAll()
        if hadUserStates {
            onUserStateChange?()
        }
    }

    public func notifyChange() {
        objectWillChange.send()
        onSessionChange?()
    }

    public struct SweptSession: Sendable {
        public let id: String
        public let projectName: String
        public let reason: SweptReason
    }

    public enum SweptReason: Sendable, Equatable {
        case directoryDeleted
        case timeout
        /// Kept for source compatibility. Dead processes now become inactive and are removed by
        /// the configured timeout rather than immediately.
        case processDead
    }

    /// Predicate for whether the process with a given pid is still alive. Swappable in tests.
    public typealias ProcessAliveCheck = @Sendable (Int32) -> Bool

    /// Default implementation: `kill(pid, 0)` checks existence without sending a signal.
    /// Only ESRCH (no such process) yields false; a permission error such as EPERM still means the
    /// process exists, so it yields true.
    public static let defaultIsProcessAlive: ProcessAliveCheck = { pid in
        guard pid > 0 else { return true }
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    /// Reconciles process presence, then removes sessions that exceeded the configured retention.
    ///
    /// A dead PID is not an immediate deletion signal. It moves the card to `.inactive`; the same
    /// timeout used for other idle sessions decides when it disappears. Pinned sessions are exempt
    /// from timeout removal. A missing working directory remains an immediate removal.
    @discardableResult
    public func sweepStale(
        timeoutSeconds: Int,
        isProcessAlive: ProcessAliveCheck = SessionManager.defaultIsProcessAlive,
        now: Date = Date()
    ) -> [SweptSession] {
        var swept: [SweptSession] = []
        var didChange = false

        for (id, session) in sessions {
            let name =
                session.originRepoName
                ?? (session.cwd as NSString?)?.lastPathComponent ?? "Session"

            if let cwd = session.cwd, !cwd.isEmpty,
                !FileManager.default.fileExists(atPath: cwd)
            {
                swept.append(SweptSession(id: id, projectName: name, reason: .directoryDeleted))
                removeSession(id: id)
                continue
            }

            let processAlive = session.pid.map(isProcessAlive)
            if session.presence != .inactive, processAlive == false {
                markInactive(session, at: now)
                didChange = true
            }

            guard timeoutSeconds > 0, !(userStates[id]?.pinned ?? false) else {
                continue
            }

            let statusForActivity = session.lastKnownStatus ?? session.status
            if session.presence != .inactive,
                statusForActivity.isRunning || statusForActivity == .permissionWaiting,
                session.presence == .live || processAlive == true
            {
                continue
            }

            let retentionDate =
                session.presence == .inactive
                ? (session.endedAt ?? session.lastActivityAt)
                : session.lastActivityAt
            if now.timeIntervalSince(retentionDate) > TimeInterval(timeoutSeconds) {
                swept.append(SweptSession(id: id, projectName: name, reason: .timeout))
                removeSession(id: id)
            }
        }

        if didChange || !swept.isEmpty {
            notifyChange()
        }
        return swept
    }

    /// How long a held-back `Stop` may sit before it is settled anyway. The deferral it
    /// guards against — socket delivery putting `Stop` a few seconds ahead of
    /// `SubagentStop` — resolves in seconds, so a minute and a half is generous.
    public static let deferredStopGracePeriod: TimeInterval = 90

    /// Settles a `Stop` that was held back and never reconsidered, and returns the ids it
    /// touched.
    ///
    /// `handleSessionIdle` defers completion while the payload reports work in flight.
    /// Nothing re-checks that decision — `Stop` fires once per turn — so when the reported
    /// work outlives the turn (a backgrounded command that never exits, a subagent whose
    /// `SubagentStart` never arrived) the card keeps a running status indefinitely.
    /// `sweepStale` exempts exactly that combination, so the retention timeout never
    /// reaches it either.
    ///
    /// The session is moved to `.idle` rather than finalized: the completion moment passed
    /// minutes ago, and `SessionFinalizer` would post a notification and play a sound that
    /// cannot be taken back. `.idle` is also the honest state — `.done` means "just
    /// finished, waiting for input".
    ///
    /// A session with an interruption pending is left alone; the queue is the real state
    /// there, and clearing it would hide a permission prompt.
    @discardableResult
    public func resolveDeferredStops(
        gracePeriod: TimeInterval = SessionManager.deferredStopGracePeriod,
        now: Date = Date()
    ) -> [String] {
        var resolved: [String] = []

        for (id, session) in sessions {
            guard let deferredAt = session.deferredStopAt else { continue }
            guard session.presence != .inactive, !session.hasPendingInterruptions else { continue }
            guard session.status.isRunning else { continue }
            // Both clocks have to be quiet. Events that do not clear the marker — a
            // Notification, a SubagentStop with no match — still move `lastActivityAt`, and
            // settling while those arrive would flip the card under a live turn.
            let quietSince = max(deferredAt, session.lastActivityAt)
            guard now.timeIntervalSince(quietSince) > gracePeriod else { continue }

            session.status = .idle
            session.deferredStopAt = nil
            session.currentTool = nil
            resolved.append(id)
        }

        if !resolved.isEmpty {
            notifyChange()
        }
        return resolved
    }

    private func markInactive(_ session: UnifiedSession, at now: Date) {
        let wasRestored = session.presence == .restored
        session.lastKnownStatus = session.lastKnownStatus ?? session.status
        session.presence = .inactive
        session.status = .idle
        session.endedAt = session.endedAt ?? (wasRestored ? session.lastActivityAt : now)
        session.doneAt = nil
        session.deferredStopAt = nil
        session.currentTool = nil
        session.pendingInterruptions.removeAll()
        session.foldRunningSubagentsToCompleted(at: now)
        session.subagentCountAtCompletion = 0
    }
}
