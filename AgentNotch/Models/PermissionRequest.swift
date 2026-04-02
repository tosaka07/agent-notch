import Foundation

struct PermissionRequest: Identifiable, Sendable {
    let id: String
    let agentType: AgentType
    let sessionId: String
    let toolName: String
    let toolInput: [String: String]
    let timestamp: Date
    let canRespond: Bool
}
