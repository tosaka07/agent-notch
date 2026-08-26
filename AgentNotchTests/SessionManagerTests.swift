import Foundation
import Testing

@testable import AgentNotchCore

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

    // MARK: - Sort / Group tests

    @Test("sortedSessions by urgency prioritizes permissionWaiting over idle")
    func sortUrgency() {
        let manager = SessionManager()
        let idle = manager.getOrCreateSession(id: "idle", agentType: .claudeCode)
        idle.status = .idle
        let waiting = manager.getOrCreateSession(id: "waiting", agentType: .claudeCode)
        waiting.status = .permissionWaiting
        let running = manager.getOrCreateSession(id: "running", agentType: .claudeCode)
        running.status = .toolRunning

        let sorted = manager.sortedSessions(order: .urgency)
        #expect(sorted.map(\.id) == ["waiting", "running", "idle"])
    }

    @Test("Pinned session always sorts first regardless of order")
    func pinnedFirst() {
        let manager = SessionManager()
        let a = manager.getOrCreateSession(id: "a", agentType: .claudeCode)
        a.status = .permissionWaiting
        let b = manager.getOrCreateSession(id: "b", agentType: .claudeCode)
        b.status = .idle

        manager.setPinned("b", true)

        let sorted = manager.sortedSessions(order: .urgency)
        #expect(sorted.first?.id == "b")
        #expect(sorted.last?.id == "a")
    }

    @Test("markDone sinks session to the bottom; new activity auto-unsinks")
    func markDoneAutoClears() {
        let manager = SessionManager()
        let a = manager.getOrCreateSession(id: "a", agentType: .claudeCode)
        a.status = .idle
        let b = manager.getOrCreateSession(id: "b", agentType: .claudeCode)
        b.status = .idle

        // Marking b as read sinks it to the bottom.
        manager.markDone("b")
        var sorted = manager.sortedSessions(order: .latestActivity)
        #expect(sorted.last?.id == "b")
        #expect(manager.isUserDone(b))

        // New activity clears the mark automatically.
        b.lastActivityAt = Date().addingTimeInterval(1)
        #expect(manager.isUserDone(b) == false)
        sorted = manager.sortedSessions(order: .latestActivity)
        #expect(sorted.first?.id == "b")
    }

    @Test("groupedSessions by status returns groups ordered by urgency")
    func groupByStatus() {
        let manager = SessionManager()
        let a = manager.getOrCreateSession(id: "a", agentType: .claudeCode)
        a.status = .idle
        let b = manager.getOrCreateSession(id: "b", agentType: .claudeCode)
        b.status = .permissionWaiting
        let c = manager.getOrCreateSession(id: "c", agentType: .claudeCode)
        c.status = .permissionWaiting

        let groups = manager.groupedSessions(order: .latestActivity, grouping: .status)
        #expect(groups.count == 2)
        // The permissionWaiting group comes first.
        #expect(groups.first?.title == SessionStatus.permissionWaiting.label)
        #expect(groups.first?.sessions.count == 2)
        #expect(groups.last?.title == SessionStatus.idle.label)
    }

    @Test("groupedSessions by agent splits by agentType")
    func groupByAgent() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "c1", agentType: .claudeCode)
        _ = manager.getOrCreateSession(id: "c2", agentType: .claudeCode)
        _ = manager.getOrCreateSession(id: "x1", agentType: .codex)

        let groups = manager.groupedSessions(order: .latestActivity, grouping: .agent)
        #expect(groups.count == 2)
    }

    @Test("removeSession also removes userState")
    func removeSessionDropsUserState() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s", agentType: .claudeCode)
        manager.setPinned("s", true)
        manager.setMuted("s", true)
        #expect(manager.userStates.count == 1)

        manager.removeSession(id: "s")
        #expect(manager.userStates.isEmpty)
    }

    @Test("setPinned false with no other state cleans up userState entry")
    func emptyUserStateCleanup() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s", agentType: .claudeCode)
        manager.setPinned("s", true)
        #expect(manager.userStates.count == 1)
        manager.setPinned("s", false)
        #expect(manager.userStates.isEmpty)
    }

    @Test("Title display preference is retained as session user state")
    func titleDisplayPreferenceIsRetained() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s", agentType: .claudeCode)

        manager.setTitleDisplayPreference("s", .latestPrompt)

        #expect(manager.userState(for: "s").titleDisplayPreference == .latestPrompt)
        #expect(manager.userStates["s"]?.titleDisplayPreference == .latestPrompt)
    }

    @Test("Title display preference survives user-state encoding")
    func titleDisplayPreferenceSurvivesEncoding() throws {
        let state = SessionUserState(titleDisplayPreference: .latestPrompt)

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(SessionUserState.self, from: data)

        #expect(restored.titleDisplayPreference == .latestPrompt)
    }

    @Test("isMuted reflects userState")
    func isMutedReflects() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s", agentType: .claudeCode)
        #expect(manager.isMuted("s") == false)
        manager.setMuted("s", true)
        #expect(manager.isMuted("s"))
    }

    @Test("Mute all applies and clears mute while preserving other user state")
    func muteAllActiveSessions() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "a", agentType: .claudeCode)
        _ = manager.getOrCreateSession(id: "b", agentType: .codex)
        manager.setPinned("a", true)

        #expect(manager.areAllActiveSessionsMuted == false)

        manager.setAllActiveSessionsMuted(true)

        #expect(manager.areAllActiveSessionsMuted)
        #expect(manager.isMuted("a"))
        #expect(manager.isMuted("b"))
        #expect(manager.userState(for: "a").pinned)

        manager.setAllActiveSessionsMuted(false)

        #expect(manager.areAllActiveSessionsMuted == false)
        #expect(manager.isMuted("a") == false)
        #expect(manager.isMuted("b") == false)
        #expect(manager.userState(for: "a").pinned)
        #expect(manager.userStates["b"] == nil)
    }

    @Test("Mute all publishes one user-state and session change")
    func muteAllPublishesOnce() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "a", agentType: .claudeCode)
        _ = manager.getOrCreateSession(id: "b", agentType: .codex)
        var userStateChangeCount = 0
        var sessionChangeCount = 0
        manager.onUserStateChange = { userStateChangeCount += 1 }
        manager.onSessionChange = { sessionChangeCount += 1 }

        manager.setAllActiveSessionsMuted(true)

        #expect(userStateChangeCount == 1)
        #expect(sessionChangeCount == 1)
    }

    @Test("Mute all ignores completed sessions and publishes nothing for an empty active list")
    func muteAllIgnoresCompletedSessions() {
        let manager = SessionManager()
        let completed = manager.getOrCreateSession(id: "completed", agentType: .claudeCode)
        completed.status = .completed
        var userStateChangeCount = 0
        var sessionChangeCount = 0
        manager.onUserStateChange = { userStateChangeCount += 1 }
        manager.onSessionChange = { sessionChangeCount += 1 }

        manager.setAllActiveSessionsMuted(true)

        #expect(!manager.areAllActiveSessionsMuted)
        #expect(manager.userStates.isEmpty)
        #expect(userStateChangeCount == 0)
        #expect(sessionChangeCount == 0)
    }

    @Test("Equal interruption times use session start and id as deterministic tie-breakers")
    func pendingInterruptionTieBreakers() throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        let first = UnifiedSession(
            id: "b-session",
            agentType: .claudeCode,
            startedAt: startedAt
        )
        let second = UnifiedSession(
            id: "a-session",
            agentType: .codex,
            startedAt: startedAt
        )
        let manager = SessionManager()
        manager.restoreSessions(from: [
            SessionSnapshot(session: first),
            SessionSnapshot(session: second),
        ])
        let receivedAt = Date(timeIntervalSince1970: 200)
        try #require(manager.session(for: first.id)).pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "first", questions: [], receivedAt: receivedAt)
        )
        try #require(manager.session(for: second.id)).pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "second", questions: [], receivedAt: receivedAt)
        )

        #expect(manager.nextPendingInterruptionSession()?.id == "a-session")
    }

    @Test("Equal interruption times prefer the session that started first")
    func pendingInterruptionStartTimeTieBreaker() throws {
        let older = UnifiedSession(
            id: "older",
            agentType: .claudeCode,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = UnifiedSession(
            id: "newer",
            agentType: .codex,
            startedAt: Date(timeIntervalSince1970: 101)
        )
        let manager = SessionManager()
        manager.restoreSessions(from: [
            SessionSnapshot(session: newer),
            SessionSnapshot(session: older),
        ])
        let receivedAt = Date(timeIntervalSince1970: 200)
        try #require(manager.session(for: older.id)).pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "older", questions: [], receivedAt: receivedAt)
        )
        try #require(manager.session(for: newer.id)).pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "newer", questions: [], receivedAt: receivedAt)
        )

        #expect(manager.nextPendingInterruptionSession()?.id == older.id)
    }

    @Test(
        "groupedSessions by team groups by teamName with leader first, and untagged sessions land in NO TEAM")
    func groupByTeam() {
        let manager = SessionManager()
        let leader = manager.getOrCreateSession(id: "leader", agentType: .claudeCode)
        leader.teamName = "alpha-team"
        let member = manager.getOrCreateSession(id: "member", agentType: .claudeCode)
        member.teamName = "alpha-team"
        member.teammateName = "researcher"
        _ = manager.getOrCreateSession(id: "solo", agentType: .claudeCode)

        let groups = manager.groupedSessions(order: .latestActivity, grouping: .team)

        #expect(groups.count == 2)
        let teamGroup = groups.first { $0.title == "alpha-team" }
        #expect(teamGroup?.sessions.map(\.id) == ["leader", "member"])
        let noTeamGroup = groups.first { $0.title == "NO TEAM" }
        #expect(noTeamGroup?.sessions.map(\.id) == ["solo"])
    }

    @Test("teamSessions(name:) returns all sessions tagged with the given teamName")
    func teamSessionsHelper() {
        let manager = SessionManager()
        let leader = manager.getOrCreateSession(id: "leader", agentType: .claudeCode)
        leader.teamName = "alpha-team"
        let member = manager.getOrCreateSession(id: "member", agentType: .claudeCode)
        member.teamName = "alpha-team"
        _ = manager.getOrCreateSession(id: "solo", agentType: .claudeCode)

        let result = manager.teamSessions(name: "alpha-team").map(\.id).sorted()
        #expect(result == ["leader", "member"])
    }

    // MARK: - reconcileSessionStart (pid-based session merging)

    @Test(
        "reconcileSessionStart merges an old session with the same pid+cwd for resume/clear/compact sources",
        arguments: ["resume", "clear", "compact"]
    )
    func reconcileSessionStartMergesSamePidForContinuationSources(source: String) {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 4242
        old.cwd = "/Users/dev/project"
        old.status = .thinking

        let merged = manager.reconcileSessionStart(
            newId: "new-session", pid: 4242, cwd: "/Users/dev/project", source: source
        )

        #expect(merged)
        #expect(manager.session(for: "old-session") == nil)
        #expect(manager.allSessions.count == 0)  // getOrCreateSession has not run for the new one yet
    }

    @Test(
        "reconcileSessionStart does NOT merge when source is startup (e.g. teammate launching in the same process)"
    )
    func reconcileSessionStartSkipsStartupSource() {
        let manager = SessionManager()
        let leader = manager.getOrCreateSession(id: "leader-session", agentType: .claudeCode)
        leader.pid = 4242
        leader.cwd = "/Users/dev/project"
        leader.status = .thinking

        // Simulates a teammate starting a fresh session inside the same process.
        // The pid matches the parent, but source=startup, so the leader session must
        // not be removed by mistake.
        let merged = manager.reconcileSessionStart(
            newId: "teammate-session", pid: 4242, cwd: "/Users/dev/project", source: "startup"
        )

        #expect(merged == false)
        #expect(manager.session(for: "leader-session") != nil)
    }

    @Test("reconcileSessionStart does NOT merge when source is nil or unknown")
    func reconcileSessionStartSkipsUnknownSource() {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 4242
        old.cwd = "/Users/dev/project"

        #expect(
            manager.reconcileSessionStart(
                newId: "new-session", pid: 4242, cwd: "/Users/dev/project", source: nil)
                == false
        )
        #expect(
            manager.reconcileSessionStart(
                newId: "new-session", pid: 4242, cwd: "/Users/dev/project", source: "something-else"
            ) == false
        )
        #expect(manager.session(for: "old-session") != nil)
    }

    @Test("reconcileSessionStart does NOT merge when cwd differs (pid alone is not trusted — security)")
    func reconcileSessionStartSkipsMismatchedCwd() {
        let manager = SessionManager()
        let victim = manager.getOrCreateSession(id: "victim-session", agentType: .claudeCode)
        victim.pid = 4242
        victim.cwd = "/Users/victim/secret-project"
        victim.status = .thinking

        // Even if an attacker sends a SessionStart spoofing the victim's pid (readable
        // via `ps`), they must not be able to merge away (delete) the victim's session
        // without knowing its cwd.
        let merged = manager.reconcileSessionStart(
            newId: "attacker-session", pid: 4242, cwd: "/tmp/attacker", source: "compact"
        )

        #expect(merged == false)
        #expect(manager.session(for: "victim-session") != nil)
    }

    @Test("reconcileSessionStart does NOT merge when cwd is unknown on either side")
    func reconcileSessionStartSkipsUnknownCwd() {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 4242
        old.cwd = nil

        #expect(
            manager.reconcileSessionStart(newId: "new-session", pid: 4242, cwd: nil, source: "compact")
                == false)
        #expect(
            manager.reconcileSessionStart(
                newId: "new-session", pid: 4242, cwd: "/Users/dev/project", source: "compact"
            ) == false
        )
        #expect(manager.session(for: "old-session") != nil)
    }

    @Test("reconcileSessionStart carries pin/mute state over to the new session id")
    func reconcileSessionStartCarriesUserState() {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 99
        old.cwd = "/Users/dev/project"
        manager.setPinned("old-session", true)

        _ = manager.reconcileSessionStart(
            newId: "new-session", pid: 99, cwd: "/Users/dev/project", source: "compact")
        _ = manager.getOrCreateSession(id: "new-session", agentType: .claudeCode)

        #expect(manager.userState(for: "new-session").pinned)
        #expect(manager.userState(for: "old-session") == .empty)
    }

    @Test("reconcileSessionStart is a no-op when pid is nil or no session shares the pid")
    func reconcileSessionStartNoOp() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)

        #expect(manager.reconcileSessionStart(newId: "s2", pid: nil, cwd: "/tmp", source: "resume") == false)
        #expect(
            manager.reconcileSessionStart(newId: "s2", pid: 12345, cwd: "/tmp", source: "resume") == false)
        #expect(manager.allSessions.count == 1)
    }

    // MARK: - sweepStale + process liveness check

    @Test("sweepStale marks a dead runtime inactive, then removes it after the configured timeout")
    func sweepStaleRetainsDeadRuntimeUntilTimeout() {
        let manager = SessionManager()
        let zombie = manager.getOrCreateSession(id: "zombie", agentType: .claudeCode)
        zombie.pid = 1
        zombie.status = .toolRunning  // frozen leftover after /compact moved to a new session_id
        zombie.cwd = "/tmp"
        let detectedAt = Date()

        let firstSweep = manager.sweepStale(
            timeoutSeconds: 3600,
            isProcessAlive: { _ in false },
            now: detectedAt
        )

        #expect(firstSweep.isEmpty)
        #expect(zombie.presence == .inactive)
        #expect(zombie.status == .idle)
        #expect(zombie.lastKnownStatus == .toolRunning)
        #expect(manager.session(for: "zombie") === zombie)

        let secondSweep = manager.sweepStale(
            timeoutSeconds: 3600,
            isProcessAlive: { _ in false },
            now: detectedAt.addingTimeInterval(3601)
        )

        #expect(secondSweep.count == 1)
        #expect(secondSweep.first?.reason == .timeout)
        #expect(manager.session(for: "zombie") == nil)
    }

    @Test("sweepStale keeps a running session whose pid is still alive")
    func sweepStaleKeepsAliveRunningSession() {
        let manager = SessionManager()
        let running = manager.getOrCreateSession(id: "running", agentType: .claudeCode)
        running.pid = 1
        running.status = .toolRunning
        running.cwd = "/tmp"

        let swept = manager.sweepStale(timeoutSeconds: 0, isProcessAlive: { _ in true })

        #expect(swept.isEmpty)
        #expect(manager.session(for: "running") != nil)
    }

    @Test("sweepStale without a known pid falls back to previous behavior (does not sweep isRunning)")
    func sweepStaleUnknownPidKeepsRunningSession() {
        let manager = SessionManager()
        let running = manager.getOrCreateSession(id: "running", agentType: .claudeCode)
        running.status = .toolRunning
        running.cwd = "/tmp"

        let swept = manager.sweepStale(timeoutSeconds: 0)

        #expect(swept.isEmpty)
        #expect(manager.session(for: "running") != nil)
    }

    @Test("Never and pin keep inactive sessions")
    func inactiveRetentionExemptions() {
        let neverManager = SessionManager()
        let neverSession = neverManager.getOrCreateSession(id: "never", agentType: .claudeCode)
        neverSession.pid = 1
        neverSession.cwd = "/tmp"
        neverSession.lastActivityAt = .distantPast

        _ = neverManager.sweepStale(
            timeoutSeconds: 0,
            isProcessAlive: { _ in false },
            now: Date()
        )
        #expect(neverSession.presence == .inactive)
        #expect(neverManager.session(for: "never") != nil)

        let pinnedManager = SessionManager()
        let pinned = pinnedManager.getOrCreateSession(id: "pinned", agentType: .codex)
        pinned.pid = 2
        pinned.cwd = "/tmp"
        pinned.lastActivityAt = .distantPast
        pinnedManager.setPinned("pinned", true)

        let swept = pinnedManager.sweepStale(
            timeoutSeconds: 1,
            isProcessAlive: { _ in false },
            now: Date()
        )
        #expect(swept.isEmpty)
        #expect(pinned.presence == .inactive)
        #expect(pinnedManager.session(for: "pinned") != nil)
    }

    @Test("A restored logical session reconnects to a different pid without creating a duplicate")
    func restoredSessionReconnectsToReplacementRuntime() {
        let source = SessionManager()
        let original = source.getOrCreateSession(id: "same-session", agentType: .codex)
        original.pid = 111
        original.cwd = "/tmp"
        original.status = .thinking
        original.lastUserPrompt = "Continue the implementation"

        let manager = SessionManager()
        manager.restoreSessions(from: source.sessionSnapshots)
        let restored = manager.session(for: "same-session")

        #expect(restored?.presence == .restored)
        #expect(restored?.status == .idle)
        #expect(restored?.lastKnownStatus == .thinking)

        let accepted = manager.prepareForRuntimeEvent(
            sessionId: "same-session",
            agentType: .codex,
            pid: 222,
            isSessionStart: true
        )

        #expect(accepted)
        #expect(manager.allSessions.count == 1)
        #expect(manager.session(for: "same-session") === restored)
        #expect(restored?.pid == 222)
        #expect(restored?.presence == .live)
        #expect(restored?.lastKnownStatus == nil)
        #expect(restored?.lastUserPrompt == "Continue the implementation")

        let staleEventAccepted = manager.prepareForRuntimeEvent(
            sessionId: "same-session",
            agentType: .codex,
            pid: 111,
            isSessionStart: false
        )
        #expect(staleEventAccepted == false)
        #expect(restored?.pid == 222)
    }

    @Test("A restored session accepts its first fresh event even when SessionStart was missed")
    func restoredSessionAcceptsFirstFreshEvent() {
        let source = SessionManager()
        let original = source.getOrCreateSession(id: "restored", agentType: .claudeCode)
        original.pid = 10

        let manager = SessionManager()
        manager.restoreSessions(from: source.sessionSnapshots)

        let accepted = manager.prepareForRuntimeEvent(
            sessionId: "restored",
            agentType: .claudeCode,
            pid: 20,
            isSessionStart: false
        )

        #expect(accepted)
        #expect(manager.session(for: "restored")?.presence == .live)
        #expect(manager.session(for: "restored")?.pid == 20)
    }

    @Test("A restored running-looking session without a pid still obeys the timeout")
    func restoredSessionWithoutPIDTimesOut() {
        let source = SessionManager()
        let original = source.getOrCreateSession(id: "unknown-runtime", agentType: .claudeCode)
        original.status = .thinking
        original.cwd = "/tmp"
        original.lastActivityAt = Date(timeIntervalSince1970: 100)

        let manager = SessionManager()
        manager.restoreSessions(from: source.sessionSnapshots)
        let swept = manager.sweepStale(
            timeoutSeconds: 60,
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(swept.count == 1)
        #expect(swept.first?.reason == .timeout)
        #expect(manager.session(for: "unknown-runtime") == nil)
    }
}
