import Foundation

public struct PendingQuestion: Sendable {
    public let toolUseId: String
    public let question: String
    public let options: [String]
    public init(toolUseId: String, question: String, options: [String]) {
        self.toolUseId = toolUseId; self.question = question; self.options = options
    }
}

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
    /// Resolved terminal app name (e.g. "iTerm2", "WezTerm")
    public var terminalAppName: String?
    /// Resolved terminal app icon (stored as Any to avoid AppKit dependency in Core)
    public var terminalAppIcon: Any?
    /// Resolved tmux pane target (e.g. "main:2.1")
    public var tmuxPaneTarget: String?
    /// Whether terminal info resolution has been attempted (prevents repeated retries)
    public var terminalInfoResolved: Bool = false
    /// Session title from transcript (customTitle or slug)
    public var sessionTitle: String?
    /// Whether session title has been resolved from transcript
    public var sessionTitleResolved: Bool = false
    public var pendingQuestion: PendingQuestion?
    public var lastActivityAt: Date

    /// `GitInfoResolver.resolve(cwd:)` で非同期に解決された git メタ情報のキャッシュ。
    /// 未解決の間は nil。`EventProcessor.backfillSession` が初回に一度だけセットする。
    public var gitInfo: GitInfo?
    /// `gitInfo` の解決が試行済みかのフラグ（リゾルブが nil を返した時の再試行を防ぐ）。
    public var gitInfoResolved: Bool = false

    public var elapsedTime: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// 解決済みの branch 名（未解決 or git 管理外なら nil）。
    public var gitBranch: String? { gitInfo?.branch }

    /// worktree の場合の元リポジトリ名。
    public var originRepoName: String? { gitInfo?.originRepoName }

    /// worktree 名（worktree でなければ nil）。
    public var worktreeName: String? { gitInfo?.worktreeName }

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
        self.lastActivityAt = startedAt
    }
}
