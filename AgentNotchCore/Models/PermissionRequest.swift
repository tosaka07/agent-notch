import Foundation

public struct PermissionRequest: Identifiable, Sendable {
    public let id: String
    public let agentType: AgentType
    public let sessionId: String
    public let toolName: String
    public let toolInput: [String: String]
    public let timestamp: Date
    public let canRespond: Bool

    public init(id: String, agentType: AgentType, sessionId: String, toolName: String, toolInput: [String: String], timestamp: Date, canRespond: Bool) {
        self.id = id; self.agentType = agentType; self.sessionId = sessionId; self.toolName = toolName
        self.toolInput = toolInput; self.timestamp = timestamp; self.canRespond = canRespond
    }
}
