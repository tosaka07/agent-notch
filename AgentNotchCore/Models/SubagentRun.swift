import Foundation

/// One subagent run embedded in its parent session (Claude's Agent/Task tool, Codex's collab thread).
/// Claude's hooks arrive with the same session_id as the parent, so a subagent is not promoted to
/// its own session; it lives in `UnifiedSession.subagents`.
public struct SubagentRun: Identifiable, Sendable {
    /// Codex sends `agent_id` in the hook, so that is used. Falls back to a synthesized UUID when Claude gives no id.
    public let id: String
    /// e.g. "Explore", "code-reviewer".
    public let agentType: String
    public let startedAt: Date
    public var endedAt: Date?
    public var status: Status
    /// When false, this run is matched to its Stop event by the agentType/FIFO fallback rather than by agentId.
    public let hasExplicitId: Bool
    /// Codex's `agent_transcript_path`. Stored but never parsed: a Codex subagent rollout
    /// duplicates the parent history inside itself.
    public var transcriptPath: String?

    public enum Status: String, Sendable {
        case running
        case completed
    }

    public init(
        id: String,
        agentType: String,
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .running,
        hasExplicitId: Bool,
        transcriptPath: String? = nil
    ) {
        self.id = id
        self.agentType = agentType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.hasExplicitId = hasExplicitId
        self.transcriptPath = transcriptPath
    }
}
