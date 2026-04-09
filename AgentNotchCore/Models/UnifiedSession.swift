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
    /// Resolved tmux pane target (e.g. "main:2.1")
    public var tmuxPaneTarget: String?
    /// Whether terminal info resolution has been attempted (prevents repeated retries)
    public var terminalInfoResolved: Bool = false
    public var pendingQuestion: PendingQuestion?
    public var lastActivityAt: Date

    public var elapsedTime: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Resolves the git directory — handles both normal repos and worktrees.
    /// Normal: `{cwd}/.git/` is a directory → returns it.
    /// Worktree: `{cwd}/.git` is a file containing `gitdir: ...` → follows the pointer.
    private var resolvedGitDir: (gitDir: String, worktreeName: String?)? {
        guard let cwd else { return nil }
        let dotGit = (cwd as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            return (dotGit, nil)
        }
        // Worktree: .git is a file like "gitdir: /path/to/main/.git/worktrees/wt-name"
        guard let content = try? String(contentsOfFile: dotGit, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              content.hasPrefix("gitdir: ") else { return nil }
        let gitDir = String(content.dropFirst("gitdir: ".count))
        // Extract worktree name from path: .../worktrees/{name}
        let parts = (gitDir as NSString).pathComponents
        let wtName: String?
        if parts.count >= 2, parts[parts.count - 2] == "worktrees" {
            wtName = parts.last
        } else {
            wtName = nil
        }
        return (gitDir, wtName)
    }

    public var gitBranch: String? {
        guard let info = resolvedGitDir else { return nil }
        let headPath = (info.gitDir as NSString).appendingPathComponent("HEAD")
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let prefix = "ref: refs/heads/"
        guard content.hasPrefix(prefix) else { return nil }
        return String(content.dropFirst(prefix.count))
    }

    /// The name of the original repository when in a worktree.
    /// Derived from the gitdir pointer: `.../original-repo/.git/worktrees/wt-name`
    public var originRepoName: String? {
        guard let info = resolvedGitDir, info.worktreeName != nil else { return nil }
        // gitDir = /path/to/original-repo/.git/worktrees/wt-name
        // Go up 3 levels: worktrees → .git → original-repo
        let p1 = (info.gitDir as NSString).deletingLastPathComponent  // .../original-repo/.git/worktrees
        let p2 = (p1 as NSString).deletingLastPathComponent           // .../original-repo/.git
        let repoPath = (p2 as NSString).deletingLastPathComponent     // .../original-repo
        let name = (repoPath as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    public var worktreeName: String? {
        resolvedGitDir?.worktreeName
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
        self.lastActivityAt = startedAt
    }
}
