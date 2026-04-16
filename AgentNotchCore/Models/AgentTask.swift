import Foundation

/// エージェントが内部で管理する task（Claude Code の TaskCreate/TaskUpdate で作成・更新される）。
public struct AgentTask: Identifiable, Sendable {
    /// Claude Code が振る連番 ID（"1", "2", ...）。
    /// TaskCreate 時点では未確定のため、セッション内の作成順で推定する。
    public let id: String
    public let subject: String
    public var status: Status

    public init(id: String, subject: String, status: Status = .pending) {
        self.id = id
        self.subject = subject
        self.status = status
    }

    public enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}
