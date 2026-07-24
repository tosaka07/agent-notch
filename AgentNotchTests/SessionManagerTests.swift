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

        // b をマーク済みにすると下に沈む
        manager.markDone("b")
        var sorted = manager.sortedSessions(order: .latestActivity)
        #expect(sorted.last?.id == "b")
        #expect(manager.isUserDone(b))

        // 新しい activity が来ると自動解除される
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
        // permissionWaiting グループが先
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

    @Test("isMuted reflects userState")
    func isMutedReflects() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s", agentType: .claudeCode)
        #expect(manager.isMuted("s") == false)
        manager.setMuted("s", true)
        #expect(manager.isMuted("s"))
    }

    @Test("groupedSessions by team groups by teamName with leader first, and untagged sessions land in NO TEAM")
    func groupByTeam() {
        let manager = SessionManager()
        let leader = manager.getOrCreateSession(id: "leader", agentType: .claudeCode)
        leader.teamName = "alpha-team"
        let member = manager.getOrCreateSession(id: "member", agentType: .claudeCode)
        member.teamName = "alpha-team"
        member.teammateName = "researcher"
        let solo = manager.getOrCreateSession(id: "solo", agentType: .claudeCode)

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

    // MARK: - #23: reconcileSessionStart (pid ベースのセッション統合)

    @Test(
        "reconcileSessionStart merges an old session with the same pid for resume/clear/compact sources",
        arguments: ["resume", "clear", "compact"]
    )
    func reconcileSessionStartMergesSamePidForContinuationSources(source: String) {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 4242
        old.status = .thinking

        let merged = manager.reconcileSessionStart(newId: "new-session", pid: 4242, source: source)

        #expect(merged)
        #expect(manager.session(for: "old-session") == nil)
        #expect(manager.allSessions.count == 0) // 新しい方はまだ getOrCreateSession されていない
    }

    @Test("reconcileSessionStart does NOT merge when source is startup (e.g. teammate launching in the same process)")
    func reconcileSessionStartSkipsStartupSource() {
        let manager = SessionManager()
        let leader = manager.getOrCreateSession(id: "leader-session", agentType: .claudeCode)
        leader.pid = 4242
        leader.status = .thinking

        // teammate が同一プロセス内で新規セッションとして起動するケースを模する。
        // pid は親と同じでも source=startup なので、リーダーセッションを誤って消してはいけない。
        let merged = manager.reconcileSessionStart(newId: "teammate-session", pid: 4242, source: "startup")

        #expect(merged == false)
        #expect(manager.session(for: "leader-session") != nil)
    }

    @Test("reconcileSessionStart does NOT merge when source is nil or unknown")
    func reconcileSessionStartSkipsUnknownSource() {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 4242

        #expect(manager.reconcileSessionStart(newId: "new-session", pid: 4242, source: nil) == false)
        #expect(manager.reconcileSessionStart(newId: "new-session", pid: 4242, source: "something-else") == false)
        #expect(manager.session(for: "old-session") != nil)
    }

    @Test("reconcileSessionStart carries pin/mute state over to the new session id")
    func reconcileSessionStartCarriesUserState() {
        let manager = SessionManager()
        let old = manager.getOrCreateSession(id: "old-session", agentType: .claudeCode)
        old.pid = 99
        manager.setPinned("old-session", true)

        _ = manager.reconcileSessionStart(newId: "new-session", pid: 99, source: "compact")
        _ = manager.getOrCreateSession(id: "new-session", agentType: .claudeCode)

        #expect(manager.userState(for: "new-session").pinned)
        #expect(manager.userState(for: "old-session") == .empty)
    }

    @Test("reconcileSessionStart is a no-op when pid is nil or no session shares the pid")
    func reconcileSessionStartNoOp() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)

        #expect(manager.reconcileSessionStart(newId: "s2", pid: nil, source: "resume") == false)
        #expect(manager.reconcileSessionStart(newId: "s2", pid: 12345, source: "resume") == false)
        #expect(manager.allSessions.count == 1)
    }

    // MARK: - #23: sweepStale + プロセス生死チェック

    @Test("sweepStale removes a running-looking session whose pid is already dead")
    func sweepStaleRemovesDeadZombieSession() {
        let manager = SessionManager()
        let zombie = manager.getOrCreateSession(id: "zombie", agentType: .claudeCode)
        zombie.pid = 1
        zombie.status = .toolRunning // /compact 等で新 session_id に移った後、凍結されたまま残る想定
        zombie.cwd = "/tmp"

        let swept = manager.sweepStale(timeoutSeconds: 0, isProcessAlive: { _ in false })

        #expect(swept.count == 1)
        #expect(swept.first?.reason == .processDead)
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
}
