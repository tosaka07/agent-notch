import Foundation

/// A task managed internally by the agent.
///
/// Tasks can arrive incrementally through Claude Code's TaskCreate/TaskUpdate
/// tools, or as an authoritative list through Claude Code's TodoWrite and
/// Codex's update_plan tools.
public struct AgentTask: Identifiable, Codable, Equatable, Sendable {
    /// Sequential ID assigned by Claude Code ("1", "2", ...). It is not yet known when the task
    /// is created via the tool, so a provisional ID is guessed from the creation order within the
    /// session (`isProvisionalId == true`). Once a first-class hook event carries the real ID,
    /// `AgentTaskReconciler` promotes it.
    public var id: String
    public let subject: String
    public var status: Status
    public var description: String?
    /// Name of the agent-teams member this task is assigned to.
    public var assignee: String?
    /// `completed_by` from the TaskCompleted hook.
    public var completedBy: String?
    public let createdAt: Date
    /// While true, `id` is a guess (the tool-derived sequence number) rather than the real ID.
    public var isProvisionalId: Bool

    public init(
        id: String,
        subject: String,
        status: Status = .pending,
        description: String? = nil,
        assignee: String? = nil,
        completedBy: String? = nil,
        createdAt: Date = Date(),
        isProvisionalId: Bool = false
    ) {
        self.id = id
        self.subject = subject
        self.status = status
        self.description = description
        self.assignee = assignee
        self.completedBy = completedBy
        self.createdAt = createdAt
        self.isProvisionalId = isProvisionalId
    }

    public enum Status: String, Codable, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}
