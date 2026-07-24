import Foundation

/// エージェントが内部で管理する task（Claude Code の TaskCreate/TaskUpdate、
/// および TaskCreated/TaskCompleted hook で作成・更新される）。
public struct AgentTask: Identifiable, Sendable {
    /// Claude Code が振る連番 ID（"1", "2", ...）。tool 経由で作成された時点では未確定のため、
    /// セッション内の作成順で推定した暫定 ID を振る（`isProvisionalId == true`）。
    /// 後から first-class hook イベントが実 ID を運んできたら `AgentTaskReconciler` が昇格させる。
    public var id: String
    public let subject: String
    public var status: Status
    public var description: String?
    /// agent teams でこの task が割り当てられたメンバー名。
    public var assignee: String?
    /// TaskCompleted hook の `completed_by`。
    public var completedBy: String?
    public let createdAt: Date
    /// true の間は `id` が推定値（tool 経由の連番）であることを示す。
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

    public enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}
