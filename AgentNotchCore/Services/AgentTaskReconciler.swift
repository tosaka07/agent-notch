import Foundation

/// TaskCreate（tool 経由、暫定連番 ID）と TaskCreated/TaskCompleted（first-class hook、実 ID）の
/// 突き合わせを行う pure function 集。MainActor 不要（`AgentTask` 配列を受け取り、新しい配列を返すだけ）。
///
/// - tool 経由が先に届き、後から hook が同じタスクの実 ID を運んでくる環境では、
///   暫定タスクの `id` を実 ID に昇格させる。
/// - hook のみが有効な環境（tool 経由が無効）では、そのまま実 ID 付きで追加される。
/// - first-class を authoritative とする。first-class 未登録環境では従来挙動（連番 provisional）が保存される。
public enum AgentTaskReconciler {
    /// 同一タスクの重複とみなす時間窓。
    static let dedupWindow: TimeInterval = 15

    /// TaskCreate(tool) / TaskCreated(hook) を既存の `tasks` に反映した新しい配列を返す。
    public static func reconcileCreated(
        tasks: [AgentTask], info: TaskCreatedInfo, now: Date = Date()
    ) -> [AgentTask] {
        var tasks = tasks

        if info.source == .hook, let taskId = info.taskId {
            // 1. 実 ID で既存タスクを探す（同一 taskId の再送・更新）。
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                if !info.description.isEmpty { tasks[index].description = info.description }
                if let assignee = info.assignee { tasks[index].assignee = assignee }
                return tasks
            }
            // 2. 暫定 ID かつ subject 一致かつ窓内のタスクがあれば実 ID に昇格。
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
            // 3. どちらも無ければ実 ID で新規追加。
            tasks.append(AgentTask(
                id: taskId, subject: info.subject, description: info.description,
                assignee: info.assignee, createdAt: now, isProvisionalId: false
            ))
            return tasks
        }

        // tool 経由（または taskId 無しの hook）: 窓内に subject 一致があれば重複として skip。
        let alreadyExists = tasks.contains {
            $0.subject == info.subject && now.timeIntervalSince($0.createdAt) <= dedupWindow
        }
        guard !alreadyExists else { return tasks }

        let nextId = String(tasks.count + 1)
        tasks.append(AgentTask(
            id: nextId, subject: info.subject, description: info.description,
            createdAt: now, isProvisionalId: true
        ))
        return tasks
    }

    /// TaskCompleted(hook) を既存の `tasks` に反映した新しい配列を返す。
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

        // 対応する TaskCreated を取りこぼした場合でも、イベント欠落耐性のため completed で追加する。
        tasks.append(AgentTask(
            id: info.taskId ?? String(tasks.count + 1),
            subject: info.subject ?? "",
            status: .completed,
            completedBy: info.completedBy,
            createdAt: now,
            isProvisionalId: info.taskId == nil
        ))
        return tasks
    }
}
