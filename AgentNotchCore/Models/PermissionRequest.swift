import Foundation

public struct PermissionRequest: Identifiable, Sendable {
    public let id: String
    public let agentType: AgentType
    public let sessionId: String
    public let toolName: String
    public let toolInput: [String: String]
    public let toolUseId: String
    public let timestamp: Date
    public let canRespond: Bool

    public init(id: String, agentType: AgentType, sessionId: String, toolName: String, toolInput: [String: String], toolUseId: String, timestamp: Date, canRespond: Bool) {
        self.id = id; self.agentType = agentType; self.sessionId = sessionId
        self.toolName = toolName; self.toolInput = toolInput; self.toolUseId = toolUseId
        self.timestamp = timestamp; self.canRespond = canRespond
    }

    /// Claude Code の Plan モード終了確認（`ExitPlanMode` ツールの承認待ち）かどうか。
    /// UI 側で "PLAN REVIEW" ラベル・専用 DotPattern に振り分けるために使う。
    public var isPlanReview: Bool { toolName == "ExitPlanMode" }
}
