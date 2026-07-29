import Foundation

public struct PermissionRequest: Identifiable, Sendable {
    public let id: String
    public let agentType: AgentType
    public let sessionId: String
    public let toolName: String
    public let toolInput: [String: String]
    /// ID of the tool invocation that triggered this request, when the agent
    /// supplied one. This is distinct from `toolUseId`, which always exists and
    /// may be a locally generated key used only for the deferred socket response.
    public let toolInvocationId: String?
    public let toolUseId: String
    public let timestamp: Date
    public let canRespond: Bool

    public init(
        id: String, agentType: AgentType, sessionId: String, toolName: String, toolInput: [String: String],
        toolUseId: String, timestamp: Date, canRespond: Bool, toolInvocationId: String? = nil
    ) {
        self.id = id
        self.agentType = agentType
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolInvocationId = toolInvocationId
        self.toolUseId = toolUseId
        self.timestamp = timestamp
        self.canRespond = canRespond
    }

    /// Whether this is Claude Code's plan-mode exit confirmation (approval pending on the
    /// `ExitPlanMode` tool). The UI uses it to switch to the "PLAN REVIEW" label and its own DotPattern.
    public var isPlanReview: Bool { toolName == "ExitPlanMode" }
}
