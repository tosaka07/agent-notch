import Foundation

public final class UnifiedSession: Identifiable, @unchecked Sendable {
    public let id: String
    public let agentType: AgentType
    public var model: String?
    public var cwd: String?
    public var status: SessionStatus
    public let startedAt: Date
    public var endedAt: Date?
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalCachedTokens: Int
    public var estimatedCost: Double
    public var toolCallCount: Int
    public var currentTool: ToolInfo?
    public var recentTools: [ToolInfo]
    public var pendingPermissions: [PermissionRequest]
    public var pid: Int32?
    public var tty: String?
    public var transcriptPath: String?

    public var elapsedTime: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    public init(
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
