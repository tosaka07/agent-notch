import Foundation

/// Pure functions that reconcile TaskCreate (via the tool, provisional sequential ID) with
/// TaskCreated/TaskCompleted (first-class hooks, real ID). No MainActor needed: they take an
/// `AgentTask` array and return a new one.
///
/// - Where the tool event arrives first and a hook later carries the same task's real ID, the
///   provisional task's `id` is promoted to the real one.
/// - Where only hooks are enabled, tasks are added with their real ID directly.
/// - First-class events are authoritative. Without them, the provisional sequential IDs persist.
public enum AgentTaskReconciler {
    /// Time window within which two events are treated as the same task.
    static let dedupWindow: TimeInterval = 15

    /// Returns a new array with TaskCreate (tool) / TaskCreated (hook) applied to `tasks`.
    public static func reconcileCreated(
        tasks: [AgentTask], info: TaskCreatedInfo, now: Date = Date()
    ) -> [AgentTask] {
        var tasks = tasks

        if info.source == .hook, let taskId = info.taskId {
            // 1. Look for an existing task by real ID (a resend or update of the same taskId).
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                if !info.description.isEmpty { tasks[index].description = info.description }
                if let assignee = info.assignee { tasks[index].assignee = assignee }
                return tasks
            }
            // 2. Promote a provisional task to the real ID if the subject matches within the window.
            if let index = tasks.firstIndex(where: {
                $0.isProvisionalId && $0.subject == info.subject
                    && now.timeIntervalSince($0.createdAt) <= dedupWindow
            }) {
                tasks[index].id = taskId
                tasks[index].isProvisionalId = false
                if !info.description.isEmpty { tasks[index].description = info.description }
                if let assignee = info.assignee { tasks[index].assignee = assignee }
                return tasks
            }
            // 3. Otherwise append a new task with the real ID.
            tasks.append(
                AgentTask(
                    id: taskId, subject: info.subject, description: info.description,
                    assignee: info.assignee, createdAt: now, isProvisionalId: false
                ))
            return tasks
        }

        // Tool event (or a hook without a taskId): skip as a duplicate if the subject matches within the window.
        let alreadyExists = tasks.contains {
            $0.subject == info.subject && now.timeIntervalSince($0.createdAt) <= dedupWindow
        }
        guard !alreadyExists else { return tasks }

        let nextId = String(tasks.count + 1)
        tasks.append(
            AgentTask(
                id: nextId, subject: info.subject, description: info.description,
                createdAt: now, isProvisionalId: true
            ))
        return tasks
    }

    /// Returns a new array with TaskCompleted (hook) applied to `tasks`.
    public static func reconcileCompleted(
        tasks: [AgentTask], info: TaskCompletedInfo, now: Date = Date()
    ) -> [AgentTask] {
        var tasks = tasks

        if let taskId = info.taskId, let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .completed
            tasks[index].completedBy = info.completedBy
            return tasks
        }
        if let subject = info.subject, let index = tasks.firstIndex(where: { $0.subject == subject }) {
            tasks[index].status = .completed
            tasks[index].completedBy = info.completedBy
            return tasks
        }

        // Add it as completed even if the matching TaskCreated was missed, so a dropped event is tolerated.
        tasks.append(
            AgentTask(
                id: info.taskId ?? String(tasks.count + 1),
                subject: info.subject ?? "",
                status: .completed,
                completedBy: info.completedBy,
                createdAt: now,
                isProvisionalId: info.taskId == nil
            ))
        return tasks
    }

    /// Replaces incremental task state with an authoritative planning-tool
    /// snapshot while preserving identity for unchanged subjects.
    ///
    /// Stable IDs keep SwiftUI rows from flashing on every plan update and let
    /// a richer TaskCreate/TaskCreated record retain its assignee and creation
    /// time when the same subject also appears in a TodoWrite snapshot.
    public static func replaceSnapshot(
        tasks: [AgentTask],
        items: [TaskListSnapshotInfo.Item],
        now: Date = Date()
    ) -> [AgentTask] {
        var usedTaskIndices = Set<Int>()
        var result: [AgentTask] = []
        var nextSnapshotId = 1

        func newSnapshotId() -> String {
            while tasks.contains(where: { $0.id == "snapshot-\(nextSnapshotId)" })
                || result.contains(where: { $0.id == "snapshot-\(nextSnapshotId)" })
            {
                nextSnapshotId += 1
            }
            defer { nextSnapshotId += 1 }
            return "snapshot-\(nextSnapshotId)"
        }

        for item in items {
            if let index = tasks.indices.first(where: {
                !usedTaskIndices.contains($0) && tasks[$0].subject == item.subject
            }) {
                usedTaskIndices.insert(index)
                var task = tasks[index]
                task.status = item.status
                if let description = item.description {
                    task.description = description
                }
                if item.status != .completed {
                    task.completedBy = nil
                }
                result.append(task)
            } else {
                result.append(
                    AgentTask(
                        id: newSnapshotId(),
                        subject: item.subject,
                        status: item.status,
                        description: item.description,
                        createdAt: now
                    )
                )
            }
        }

        return result
    }
}
