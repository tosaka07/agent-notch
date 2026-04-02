import Foundation

@Observable
final class UnifiedSession: Identifiable, @unchecked Sendable {
    let id: String
    let agentType: AgentType
    var model: String?
    var cwd: String?
    var status: SessionStatus
    let startedAt: Date
    var endedAt: Date?
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalCachedTokens: Int
    var estimatedCost: Double
    var toolCallCount: Int
    var currentTool: ToolInfo?
    var recentTools: [ToolInfo]
    var pendingPermissions: [PermissionRequest]
    var pid: Int32?
    var tty: String?
    var transcriptPath: String?

    var elapsedTime: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    init(
        id: String,
        agentType: AgentType,
        model: String? = nil,
        cwd: String? = nil,
        status: SessionStatus = .starting,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.agentType = agentType
        self.model = model
        self.cwd = cwd
        self.status = status
        self.startedAt = startedAt
        self.endedAt = nil
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.totalCachedTokens = 0
        self.estimatedCost = 0
        self.toolCallCount = 0
        self.currentTool = nil
        self.recentTools = []
        self.pendingPermissions = []
        self.pid = nil
        self.tty = nil
        self.transcriptPath = nil
    }
}
