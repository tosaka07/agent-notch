import Foundation
import Testing

@testable import AgentNotchCore

@Suite("AgentTaskReconciler Tests")
struct AgentTaskReconcilerTests {
    @Test("tool creates a provisional task, then hook TaskCreated with same subject promotes id")
    func toolThenHookPromotesId() {
        let now = Date()
        let toolInfo = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "desc",
            taskId: nil, assignee: nil, teamName: nil, source: .tool
        )
        var tasks = AgentTaskReconciler.reconcileCreated(tasks: [], info: toolInfo, now: now)
        #expect(tasks.count == 1)
        #expect(tasks[0].id == "1")
        #expect(tasks[0].isProvisionalId)

        let hookInfo = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "richer desc",
            taskId: "task-99", assignee: "researcher", teamName: "alpha", source: .hook
        )
        tasks = AgentTaskReconciler.reconcileCreated(
            tasks: tasks, info: hookInfo, now: now.addingTimeInterval(2))

        #expect(tasks.count == 1)
        #expect(tasks[0].id == "task-99")
        #expect(tasks[0].isProvisionalId == false)
        #expect(tasks[0].description == "richer desc")
        #expect(tasks[0].assignee == "researcher")
    }

    @Test("hook TaskCreated arrives first, then tool TaskCreate with same subject is skipped")
    func hookThenToolSkipsDuplicate() {
        let now = Date()
        let hookInfo = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "desc",
            taskId: "task-1", assignee: nil, teamName: nil, source: .hook
        )
        var tasks = AgentTaskReconciler.reconcileCreated(tasks: [], info: hookInfo, now: now)
        #expect(tasks.count == 1)

        let toolInfo = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "desc",
            taskId: nil, assignee: nil, teamName: nil, source: .tool
        )
        tasks = AgentTaskReconciler.reconcileCreated(
            tasks: tasks, info: toolInfo, now: now.addingTimeInterval(2))

        // Skipped as a duplicate; the single existing entry remains.
        #expect(tasks.count == 1)
        #expect(tasks[0].id == "task-1")
    }

    @Test("same subject outside the 15s dedup window is treated as a new task")
    func outsideDedupWindowAppendsNew() {
        let now = Date()
        let first = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "desc",
            taskId: nil, assignee: nil, teamName: nil, source: .tool
        )
        var tasks = AgentTaskReconciler.reconcileCreated(tasks: [], info: first, now: now)
        #expect(tasks.count == 1)

        // A same-named task 20 seconds later is not a duplicate and is added.
        let second = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "desc again",
            taskId: nil, assignee: nil, teamName: nil, source: .tool
        )
        tasks = AgentTaskReconciler.reconcileCreated(
            tasks: tasks, info: second, now: now.addingTimeInterval(20))

        #expect(tasks.count == 2)
        #expect(tasks[1].id == "2")
        #expect(tasks[1].isProvisionalId)
    }

    @Test("first-class TaskCreated with no matching provisional task appends directly with real id")
    func hookOnlyEnvironmentAppendsDirectly() {
        let now = Date()
        let hookInfo = TaskCreatedInfo(
            sessionId: "s1", subject: "Ship feature", description: "desc",
            taskId: "task-42", assignee: "lead", teamName: "alpha", source: .hook
        )
        let tasks = AgentTaskReconciler.reconcileCreated(tasks: [], info: hookInfo, now: now)

        #expect(tasks.count == 1)
        #expect(tasks[0].id == "task-42")
        #expect(tasks[0].isProvisionalId == false)
        #expect(tasks[0].assignee == "lead")
    }

    @Test("tool-only environment (no first-class hooks) preserves legacy sequential provisional ids")
    func toolOnlyBackwardCompatibility() {
        let now = Date()
        var tasks: [AgentTask] = []
        for subject in ["Task A", "Task B", "Task C"] {
            let info = TaskCreatedInfo(
                sessionId: "s1", subject: subject, description: "",
                taskId: nil, assignee: nil, teamName: nil, source: .tool
            )
            tasks = AgentTaskReconciler.reconcileCreated(tasks: tasks, info: info, now: now)
        }

        #expect(tasks.map(\.id) == ["1", "2", "3"])
        #expect(tasks.allSatisfy { $0.isProvisionalId })
    }

    @Test("reconcileCompleted marks matching taskId as completed with completedBy")
    func completedMatchesByTaskId() {
        let now = Date()
        let created = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "",
            taskId: "task-1", assignee: nil, teamName: nil, source: .hook
        )
        var tasks = AgentTaskReconciler.reconcileCreated(tasks: [], info: created, now: now)

        let completedInfo = TaskCompletedInfo(
            sessionId: "s1", taskId: "task-1", subject: nil, completedBy: "researcher", teamName: nil
        )
        tasks = AgentTaskReconciler.reconcileCompleted(
            tasks: tasks, info: completedInfo, now: now.addingTimeInterval(5))

        #expect(tasks[0].status == .completed)
        #expect(tasks[0].completedBy == "researcher")
    }

    @Test("reconcileCompleted falls back to subject match when taskId is absent")
    func completedFallsBackToSubject() {
        let now = Date()
        let created = TaskCreatedInfo(
            sessionId: "s1", subject: "Fix auth", description: "",
            taskId: nil, assignee: nil, teamName: nil, source: .tool
        )
        var tasks = AgentTaskReconciler.reconcileCreated(tasks: [], info: created, now: now)

        let completedInfo = TaskCompletedInfo(
            sessionId: "s1", taskId: nil, subject: "Fix auth", completedBy: "lead", teamName: nil
        )
        tasks = AgentTaskReconciler.reconcileCompleted(
            tasks: tasks, info: completedInfo, now: now.addingTimeInterval(5))

        #expect(tasks[0].status == .completed)
        #expect(tasks[0].completedBy == "lead")
    }

    @Test("reconcileCompleted appends a completed task when no matching task is found (missed TaskCreated)")
    func completedAppendsWhenMissing() {
        let completedInfo = TaskCompletedInfo(
            sessionId: "s1", taskId: "task-1", subject: nil, completedBy: "researcher", teamName: nil
        )
        let tasks = AgentTaskReconciler.reconcileCompleted(tasks: [], info: completedInfo)

        #expect(tasks.count == 1)
        #expect(tasks[0].id == "task-1")
        #expect(tasks[0].status == .completed)
        #expect(tasks[0].completedBy == "researcher")
    }

    @Test("authoritative snapshot preserves matching identities and removes absent tasks")
    func snapshotPreservesIdentityAndReplacesContents() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let existing = [
            AgentTask(
                id: "task-real",
                subject: "Keep me",
                status: .pending,
                description: "Richer description",
                assignee: "worker",
                createdAt: createdAt
            ),
            AgentTask(id: "obsolete", subject: "Remove me", createdAt: createdAt),
        ]

        let tasks = AgentTaskReconciler.replaceSnapshot(
            tasks: existing,
            items: [
                .init(subject: "Keep me", status: .inProgress),
                .init(subject: "New task", status: .pending),
            ],
            now: Date(timeIntervalSince1970: 2_000)
        )

        #expect(tasks.map(\.subject) == ["Keep me", "New task"])
        #expect(tasks[0].id == "task-real")
        #expect(tasks[0].createdAt == createdAt)
        #expect(tasks[0].description == "Richer description")
        #expect(tasks[0].assignee == "worker")
        #expect(tasks[0].status == .inProgress)
        #expect(tasks[1].id == "snapshot-1")
    }

    @Test("empty authoritative snapshot clears the task list")
    func emptySnapshotClearsTasks() {
        let tasks = AgentTaskReconciler.replaceSnapshot(
            tasks: [AgentTask(id: "1", subject: "Done")],
            items: []
        )

        #expect(tasks.isEmpty)
    }
}
