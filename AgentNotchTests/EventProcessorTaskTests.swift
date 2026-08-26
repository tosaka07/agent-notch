import AgentNotchCore
import Foundation
import Testing

@testable import AgentNotch

/// Covers the event routes that reach session state without going through a status transition:
/// the task list, compaction, session end, permission mode, and team attribution.
///
/// Every case is driven through `ClaudeEventParser.parse` and `EventProcessor.apply`, the same
/// path a real hook takes, so the payload keys are pinned too — a renamed key in the hook JSON is
/// exactly the kind of break that a hand-built event value would hide.
@Suite("EventProcessor task and lifecycle routing")
@MainActor
struct EventProcessorTaskTests {
    private func apply(_ payload: [String: Any], to manager: SessionManager) {
        EventProcessor.apply(
            ClaudeEventParser.parse(payload),
            agentType: .claudeCode,
            manager: manager
        )
    }

    private func startedSession(
        _ id: String = "s1",
        in manager: SessionManager
    ) -> UnifiedSession {
        apply(["hook_event_name": "SessionStart", "session_id": id], to: manager)
        return manager.session(for: id)!
    }

    // MARK: - Task list

    /// The tool route fires before Claude Code has assigned an ID, so the task is held under a
    /// provisional one. Losing that would leave the card unable to show work in progress.
    @Test("A task created through the tool is held under a provisional id")
    func taskCreatedViaTool() {
        let manager = SessionManager()
        let session = startedSession(in: manager)

        apply(
            [
                "hook_event_name": "PreToolUse",
                "session_id": "s1",
                "tool_name": "TaskCreate",
                "tool_input": ["subject": "Ship the icon", "description": "swap in the .icon"],
            ], to: manager)

        #expect(session.tasks.count == 1)
        #expect(session.tasks[0].subject == "Ship the icon")
        #expect(session.tasks[0].description == "swap in the .icon")
        #expect(session.tasks[0].status == .pending)
        #expect(session.tasks[0].isProvisionalId)
    }

    @Test("A task created through the hook carries its real id, assignee and team")
    func taskCreatedViaHook() {
        let manager = SessionManager()
        let session = startedSession(in: manager)

        apply(
            [
                "hook_event_name": "TaskCreated",
                "session_id": "s1",
                "task_id": "7",
                "task_title": "Raise coverage",
                "task_description": "codec first",
                "assigned_to": "tester",
                "team_name": "quality",
            ], to: manager)

        #expect(session.tasks.count == 1)
        #expect(session.tasks[0].id == "7")
        #expect(!session.tasks[0].isProvisionalId)
        #expect(session.tasks[0].assignee == "tester")
        #expect(session.teamName == "quality")
    }

    /// Task events can arrive before any SessionStart — a hook can fire first. Dropping them
    /// would silently lose the task list for that session.
    @Test("A task event for an unknown session creates the session")
    func taskCreatedCreatesMissingSession() {
        let manager = SessionManager()

        apply(
            [
                "hook_event_name": "TaskCreated",
                "session_id": "fresh",
                "task_id": "1",
                "task_title": "First",
            ], to: manager)

        let session = manager.session(for: "fresh")
        #expect(session?.tasks.count == 1)
        #expect(session?.agentType == .claudeCode)
    }

    @Test("An update moves an existing task to its new status")
    func taskUpdated() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        apply(
            [
                "hook_event_name": "TaskCreated", "session_id": "s1",
                "task_id": "3", "task_title": "Move me",
            ], to: manager)

        apply(
            [
                "hook_event_name": "PreToolUse",
                "session_id": "s1",
                "tool_name": "TaskUpdate",
                "tool_input": ["taskId": "3", "status": "in_progress"],
            ], to: manager)

        #expect(session.tasks[0].status == .inProgress)
    }

    /// An unrecognised status must leave the task alone rather than reset it: the status drives
    /// what the card shows, and a silent downgrade to pending would misreport running work.
    @Test("An unknown status leaves the task untouched")
    func taskUpdateIgnoresUnknownStatus() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        apply(
            [
                "hook_event_name": "TaskCreated", "session_id": "s1",
                "task_id": "3", "task_title": "Keep me",
            ], to: manager)
        apply(
            [
                "hook_event_name": "PreToolUse", "session_id": "s1",
                "tool_name": "TaskUpdate",
                "tool_input": ["taskId": "3", "status": "teleported"],
            ], to: manager)

        #expect(session.tasks[0].status == .pending)
    }

    @Test("An update for an id that does not exist is a no-op")
    func taskUpdateForUnknownIdIsIgnored() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        apply(
            [
                "hook_event_name": "TaskCreated", "session_id": "s1",
                "task_id": "3", "task_title": "Only task",
            ], to: manager)

        apply(
            [
                "hook_event_name": "PreToolUse", "session_id": "s1",
                "tool_name": "TaskUpdate",
                "tool_input": ["taskId": "999", "status": "completed"],
            ], to: manager)

        #expect(session.tasks.count == 1)
        #expect(session.tasks[0].status == .pending)
    }

    @Test("Completion marks the task done and records who finished it")
    func taskCompleted() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        apply(
            [
                "hook_event_name": "TaskCreated", "session_id": "s1",
                "task_id": "5", "task_title": "Finish me",
            ], to: manager)

        apply(
            [
                "hook_event_name": "TaskCompleted",
                "session_id": "s1",
                "task_id": "5",
                "task_title": "Finish me",
                "completed_by": "worker",
                "team_name": "quality",
            ], to: manager)

        #expect(session.tasks[0].status == .completed)
        #expect(session.tasks[0].completedBy == "worker")
        #expect(session.teamName == "quality")
    }

    /// The team name is the first one seen. A later event naming a different team is a teammate
    /// reporting in, not a reassignment of the session.
    @Test("The team name is kept from the first event that names one")
    func teamNameIsNotOverwritten() {
        let manager = SessionManager()
        let session = startedSession(in: manager)

        apply(
            [
                "hook_event_name": "TaskCreated", "session_id": "s1",
                "task_id": "1", "task_title": "a", "team_name": "first",
            ], to: manager)
        apply(
            [
                "hook_event_name": "TaskCompleted", "session_id": "s1",
                "task_id": "1", "team_name": "second",
            ], to: manager)

        #expect(session.teamName == "first")
    }

    /// TodoWrite is authoritative: it replaces the list rather than appending, or a re-plan would
    /// accumulate every task the session ever had.
    @Test("A planning snapshot replaces the whole task list")
    func taskListReplaced() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        apply(
            [
                "hook_event_name": "TaskCreated", "session_id": "s1",
                "task_id": "1", "task_title": "stale",
            ], to: manager)

        apply(
            [
                "hook_event_name": "PreToolUse",
                "session_id": "s1",
                "tool_name": "TodoWrite",
                "tool_input": [
                    "todos": [
                        ["content": "one", "status": "completed"],
                        ["content": "two", "status": "in_progress"],
                        ["content": "three", "status": "pending"],
                    ]
                ],
            ], to: manager)

        #expect(session.tasks.map(\.subject) == ["one", "two", "three"])
        #expect(session.tasks.map(\.status) == [.completed, .inProgress, .pending])
    }

    // MARK: - Lifecycle

    @Test("Compaction sets the compacting status and finishing returns to thinking")
    func compactionRoundTrip() {
        let manager = SessionManager()
        let session = startedSession(in: manager)

        apply(["hook_event_name": "PreCompact", "session_id": "s1"], to: manager)
        #expect(session.status == .compacting)

        apply(["hook_event_name": "PostCompact", "session_id": "s1"], to: manager)
        #expect(session.status == .thinking)
    }

    /// The rule that a pending permission outranks every other status applies to compaction too,
    /// or the card would stop asking for the approval the agent is blocked on.
    @Test("Compaction does not override a pending permission")
    func compactionKeepsPendingPermission() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        apply(
            [
                "hook_event_name": "PermissionRequest",
                "session_id": "s1",
                "tool_name": "Bash",
                "tool_use_id": "t1",
                "tool_input": ["command": "ls"],
            ], to: manager)
        let blocked = session.status

        apply(["hook_event_name": "PostCompact", "session_id": "s1"], to: manager)

        #expect(session.status == blocked)
    }

    @Test("Session end removes the session")
    func sessionEndedRemovesSession() {
        let manager = SessionManager()
        _ = startedSession(in: manager)

        apply(["hook_event_name": "SessionEnd", "session_id": "s1"], to: manager)

        #expect(manager.session(for: "s1") == nil)
    }

    @Test("An unrecognised hook is ignored rather than creating a session")
    func unknownEventIsIgnored() {
        let manager = SessionManager()

        apply(["hook_event_name": "SomethingNew", "session_id": "ghost"], to: manager)

        #expect(manager.session(for: "ghost") == nil)
    }

    // MARK: - Permission mode

    @Test("permission_mode on any event is applied to the session")
    func permissionModeIsApplied() {
        let manager = SessionManager()
        let session = startedSession(in: manager)

        EventProcessor.applyPermissionMode(
            sessionId: "s1", rawMode: "acceptEdits", manager: manager
        )

        #expect(session.permissionMode == .acceptEdits)
    }

    @Test("An unparsable or absent mode changes nothing")
    func permissionModeIgnoresBadInput() {
        let manager = SessionManager()
        let session = startedSession(in: manager)
        let before = session.permissionMode

        EventProcessor.applyPermissionMode(sessionId: "s1", rawMode: nil, manager: manager)
        EventProcessor.applyPermissionMode(sessionId: "s1", rawMode: "nonsense", manager: manager)

        #expect(session.permissionMode == before)
    }

    /// A mode for a session that has not started yet is dropped on purpose: creating a session
    /// from it would produce a card with no agent, project, or prompt behind it.
    @Test("A mode for an unknown session does not create one")
    func permissionModeForUnknownSessionIsDropped() {
        let manager = SessionManager()

        EventProcessor.applyPermissionMode(
            sessionId: "absent", rawMode: "acceptEdits", manager: manager
        )

        #expect(manager.session(for: "absent") == nil)
    }
}
