import Foundation

/// 親セッションに埋め込まれる subagent の 1 実行（Claude の Agent/Task ツール、Codex の collab スレッド）。
/// Claude の hook は親と同じ session_id で届くため、subagent は独立セッション化せず
/// `UnifiedSession.subagents` に埋め込む。
public struct SubagentRun: Identifiable, Sendable {
    /// Codex は `agent_id` が hook から届くのでそれを使う。Claude 側で id が取れない場合は合成 UUID。
    public let id: String
    /// "Explore", "code-reviewer" 等。
    public let agentType: String
    public let startedAt: Date
    public var endedAt: Date?
    public var status: Status
    /// false の場合、この run は agentId ではなく agentType/FIFO のフォールバックで Stop と対応付けられる対象。
    public let hasExplicitId: Bool
    /// Codex の `agent_transcript_path`。保持のみ行い、解析はしない
    /// （Codex の subagent rollout は親履歴を複製して含む罠があるため）。
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
