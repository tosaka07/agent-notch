import Foundation

public struct PendingQuestion: Sendable {
    public let toolUseId: String
    /// AskUserQuestion は 1-4 問まとめて送られる。
    public let questions: [AskQuestionInfo.Question]

    public init(toolUseId: String, questions: [AskQuestionInfo.Question]) {
        self.toolUseId = toolUseId
        self.questions = questions
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
    /// 最初のユーザーメッセージ（セッションの目的）
    public var firstUserPrompt: String?
    /// firstUserPrompt の解決が試行済みか
    public var firstUserPromptResolved: Bool = false
    /// 最新のユーザーメッセージ（lastUserMessage 用）
    public var lastUserPrompt: String?
    /// 完了時の最後のアシスタントメッセージ（SessionFinalizer がセット）
    public var lastAssistantMessage: String?
    /// セッションが done になった瞬間の時刻（完了アニメーションの開始基準）
    public var doneAt: Date?
    public var pendingQuestion: PendingQuestion?
    public var lastActivityAt: Date
    /// 現在のパーミッションモード（`default` / `acceptEdits` / `plan` / `dontAsk` / `bypassPermissions`）。
    /// hook イベント共通フィールド `permission_mode` から反映される。未受信の間は nil。
    public var permissionMode: PermissionMode?
    /// エージェント内部のタスク一覧（TaskCreate/TaskUpdate で管理される）。
    public var tasks: [AgentTask] = []

    /// 実行中・完了済みの subagent 一覧（古い順）。completed は最大 50 件まで。
    public var subagents: [SubagentRun] = []
    /// セッション完了（`foldRunningSubagentsToCompleted`）時点で実行中だった subagent 数。
    /// 完了通知の表示中、左翼の swarm 表示を維持するために使う（compact UI 側）。
    public var subagentCountAtCompletion: Int = 0
    /// agent teams のチーム名（TeammateIdle / TaskCreated/TaskCompleted の team_name から反映）。
    public var teamName: String?
    /// agent teams でのこのセッションのメンバー名（TeammateIdle の teammate_name から反映）。
    /// nil ならチームリーダー（または team 未所属）とみなす。
    public var teammateName: String?

    public var runningSubagentCount: Int {
        subagents.filter { $0.status == .running }.count
    }

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

    /// SubagentStart を記録する。
    public func startSubagent(agentType: String, agentId: String?, at date: Date = Date()) {
        subagents.append(SubagentRun(
            id: agentId ?? UUID().uuidString,
            agentType: agentType,
            startedAt: date,
            hasExplicitId: agentId != nil
        ))
    }

    /// SubagentStop を対応する run に反映する。
    /// マッチ優先順: agentId 一致 → agentType 一致の最古 running → 最古の running → 無ければ false（二重 Stop 耐性）。
    @discardableResult
    public func stopSubagent(
        agentId: String?, agentType: String?, transcriptPath: String?, at date: Date = Date()
    ) -> Bool {
        var matchedIndex: Int?

        if let agentId {
            matchedIndex = subagents.firstIndex { $0.status == .running && $0.id == agentId }
        }
        if matchedIndex == nil, let agentType {
            matchedIndex = oldestRunningIndex { $0.agentType == agentType }
        }
        if matchedIndex == nil {
            matchedIndex = oldestRunningIndex { _ in true }
        }

        guard let index = matchedIndex else { return false }
        subagents[index].status = .completed
        subagents[index].endedAt = date
        if let transcriptPath { subagents[index].transcriptPath = transcriptPath }
        trimCompletedSubagents()
        return true
    }

    /// 実行中の subagent を全て completed に畳む（セッション終了時に使用）。
    /// 畳む直前の実行数を `subagentCountAtCompletion` に記録する。
    public func foldRunningSubagentsToCompleted(at date: Date = Date()) {
        subagentCountAtCompletion = runningSubagentCount
        for index in subagents.indices where subagents[index].status == .running {
            subagents[index].status = .completed
            subagents[index].endedAt = date
        }
    }

    private func oldestRunningIndex(where predicate: (SubagentRun) -> Bool) -> Int? {
        subagents.indices
            .filter { subagents[$0].status == .running && predicate(subagents[$0]) }
            .min { subagents[$0].startedAt < subagents[$1].startedAt }
    }

    /// completed を古い順に落として最大 50 件に制限する。
    private func trimCompletedSubagents() {
        guard subagents.count > 50 else { return }
        var overflow = subagents.count - 50
        let completedOldestFirst = subagents.indices
            .filter { subagents[$0].status == .completed }
            .sorted { (subagents[$0].endedAt ?? .distantPast) < (subagents[$1].endedAt ?? .distantPast) }

        var toRemove = Set<Int>()
        for index in completedOldestFirst {
            guard overflow > 0 else { break }
            toRemove.insert(index)
            overflow -= 1
        }
        guard !toRemove.isEmpty else { return }
        subagents = subagents.enumerated().filter { !toRemove.contains($0.offset) }.map(\.element)
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
