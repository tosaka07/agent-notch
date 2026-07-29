import Foundation

/// How the currently displayed question can be answered.
///
/// Observation and response are deliberately separate capabilities. Codex CLI
/// hooks and rollout files can reveal a question without exposing the owning
/// request channel; in that case Agent Notch may display it, but the answer
/// still belongs in the terminal. A later App Server / Codex App attachment can
/// upgrade the same question to `.direct`.
public enum QuestionResponseMode: String, Sendable, Equatable {
    case direct
    case terminalOnly
}

/// Delivery state owned by the question lifecycle rather than a button view.
public enum QuestionPhase: String, Sendable, Equatable {
    case waiting
    case submitting
    case expired
}

public struct PendingQuestion: Sendable {
    public let toolUseId: String
    /// IDs observed for the same logical question across hook routes. Claude's PreToolUse and
    /// PermissionRequest IDs differ, while PostToolUse returns the former.
    public var correlationToolUseIds: Set<String>
    /// AskUserQuestion sends 1-4 questions at once.
    public let questions: [AskQuestionInfo.Question]
    /// When this request entered the interruption queue. Navigation across sessions uses it
    /// to preserve arrival order instead of letting the latest request steal the panel.
    public var receivedAt: Date
    /// Predicted time the hook stops waiting for a response (receipt time + `HookHandler.recvTimeoutSeconds`).
    /// Used for the remaining-time display in the UI.
    public let expiresAt: Date
    public var responseMode: QuestionResponseMode
    public var phase: QuestionPhase

    /// Compatibility accessors keep existing Claude hook call sites compact
    /// while the state itself remains mutually exclusive.
    public var isExpired: Bool {
        get { phase == .expired }
        set {
            if newValue {
                phase = .expired
            } else if phase == .expired {
                phase = .waiting
            }
        }
    }

    public var isSubmitting: Bool {
        get { phase == .submitting }
        set {
            if newValue {
                phase = .submitting
            } else if phase == .submitting {
                phase = .waiting
            }
        }
    }

    public init(
        toolUseId: String,
        questions: [AskQuestionInfo.Question],
        correlationToolUseIds: Set<String>? = nil,
        receivedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(TimeInterval(HookHandler.recvTimeoutSeconds)),
        responseMode: QuestionResponseMode = .direct,
        isExpired: Bool = false,
        isSubmitting: Bool = false
    ) {
        self.toolUseId = toolUseId
        self.correlationToolUseIds = correlationToolUseIds ?? [toolUseId]
        self.questions = questions
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.responseMode = responseMode
        if isExpired {
            phase = .expired
        } else if isSubmitting {
            phase = .submitting
        } else {
            phase = .waiting
        }
    }
}

/// One item in a session's user-interruption queue.
///
/// Permission requests and questions share one arrival order. Keeping the order in the model
/// prevents a newly arrived item of the other kind from being inserted above the card the user
/// is already answering.
public enum PendingInterruption: Sendable {
    public enum Kind: Sendable, Equatable {
        case permission
        case question
    }

    case permission(PermissionRequest)
    case question(PendingQuestion)

    public var kind: Kind {
        switch self {
        case .permission: .permission
        case .question: .question
        }
    }

    public var toolUseId: String {
        switch self {
        case .permission(let permission): permission.toolUseId
        case .question(let question): question.toolUseId
        }
    }

    public var id: String {
        switch kind {
        case .permission: "permission:\(toolUseId)"
        case .question: "question:\(toolUseId)"
        }
    }

    public var receivedAt: Date {
        switch self {
        case .permission(let permission): permission.timestamp
        case .question(let question): question.receivedAt
        }
    }
}

/// FIFO queue for everything in a session that needs a user response.
///
/// Its small interface owns ordering, duplicate transport observations, targeted updates, and
/// removal. Views only read `first`; event adapters enqueue or update by tool-use ID.
public struct PendingInterruptionQueue: Sendable {
    public private(set) var items: [PendingInterruption] = []

    public init() {}

    public var first: PendingInterruption? { items.first }
    public var isEmpty: Bool { items.isEmpty }

    public var permissions: [PermissionRequest] {
        items.compactMap {
            guard case .permission(let permission) = $0 else { return nil }
            return permission
        }
    }

    public var questions: [PendingQuestion] {
        items.compactMap {
            guard case .question(let question) = $0 else { return nil }
            return question
        }
    }

    /// Adds an approval unless that exact transport request is already queued.
    @discardableResult
    public mutating func enqueue(_ permission: PermissionRequest) -> Bool {
        guard !contains(kind: .permission, toolUseId: permission.toolUseId) else { return false }
        items.append(.permission(permission))
        return true
    }

    /// Adds or refreshes a question.
    ///
    /// Claude may describe one AskUserQuestion first through PreToolUse and then through
    /// PermissionRequest with a different local transport ID. `coalesceMatchingContent` replaces
    /// that observation in place, preserving its original queue position. Codex has stable record
    /// correlation and therefore leaves this off so genuinely separate requests can coexist.
    @discardableResult
    public mutating func enqueue(
        _ question: PendingQuestion,
        coalesceMatchingContent: Bool = false
    ) -> Bool {
        if let index = index(kind: .question, toolUseId: question.toolUseId) {
            if case .question(var queued) = items[index],
                queued.toolUseId != question.toolUseId
            {
                // The incoming ID is an alias for a newer response-channel
                // identity. A replay of the earlier observation must not make
                // future answers target the non-responsive hook again.
                queued.correlationToolUseIds.formUnion(question.correlationToolUseIds)
                items[index] = .question(queued)
                return false
            }

            var replacement = question
            if case .question(let queued) = items[index] {
                replacement.correlationToolUseIds.formUnion(queued.correlationToolUseIds)
            }
            replacement.receivedAt = items[index].receivedAt
            items[index] = .question(replacement)
            return false
        }

        if coalesceMatchingContent,
            let index = items.lastIndex(where: { item in
                guard case .question(let queued) = item else { return false }
                return queued.questions == question.questions
            })
        {
            var replacement = question
            if case .question(let queued) = items[index] {
                replacement.correlationToolUseIds.formUnion(queued.correlationToolUseIds)
            }
            replacement.receivedAt = items[index].receivedAt
            items[index] = .question(replacement)
            return false
        }

        items.append(.question(question))
        return true
    }

    public func contains(kind: PendingInterruption.Kind, toolUseId: String) -> Bool {
        index(kind: kind, toolUseId: toolUseId) != nil
    }

    public func question(toolUseId: String) -> PendingQuestion? {
        guard let index = index(kind: .question, toolUseId: toolUseId),
            case .question(let question) = items[index]
        else { return nil }
        return question
    }

    @discardableResult
    public mutating func updateQuestion(
        toolUseId: String,
        _ mutate: (inout PendingQuestion) -> Void
    ) -> Bool {
        guard let index = index(kind: .question, toolUseId: toolUseId),
            case .question(var question) = items[index]
        else { return false }
        mutate(&question)
        items[index] = .question(question)
        return true
    }

    @discardableResult
    public mutating func updatePermission(
        toolUseId: String,
        _ transform: (PermissionRequest) -> PermissionRequest
    ) -> Bool {
        guard let index = index(kind: .permission, toolUseId: toolUseId),
            case .permission(let permission) = items[index]
        else { return false }
        items[index] = .permission(transform(permission))
        return true
    }

    mutating func replacePermissions(with replacements: [PermissionRequest]) {
        let insertionIndex =
            items.firstIndex(where: {
                if case .permission = $0 { return true }
                return false
            }) ?? items.endIndex
        items.removeAll {
            if case .permission = $0 { return true }
            return false
        }
        items.insert(
            contentsOf: replacements.map(PendingInterruption.permission),
            at: min(insertionIndex, items.endIndex)
        )
    }

    mutating func replaceFirstQuestion(with replacement: PendingQuestion?) {
        guard
            let index = items.firstIndex(where: {
                if case .question = $0 { return true }
                return false
            })
        else {
            if let replacement {
                items.append(.question(replacement))
            }
            return
        }

        guard var replacement else {
            items.remove(at: index)
            return
        }
        if case .question(let queued) = items[index] {
            replacement.correlationToolUseIds.formUnion(queued.correlationToolUseIds)
            replacement.receivedAt = queued.receivedAt
        }
        items[index] = .question(replacement)
    }

    @discardableResult
    public mutating func remove(
        kind: PendingInterruption.Kind,
        toolUseId: String
    ) -> Bool {
        guard let index = index(kind: kind, toolUseId: toolUseId) else { return false }
        items.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func removeAll(
        where shouldRemove: (PendingInterruption) -> Bool
    ) -> Int {
        let oldCount = items.count
        items.removeAll(where: shouldRemove)
        return oldCount - items.count
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    private func index(
        kind: PendingInterruption.Kind,
        toolUseId: String
    ) -> Int? {
        items.firstIndex { item in
            guard item.kind == kind else { return false }
            switch item {
            case .permission(let permission):
                return permission.toolUseId == toolUseId
            case .question(let question):
                return question.correlationToolUseIds.contains(toolUseId)
            }
        }
    }
}

public final class UnifiedSession: Identifiable, @unchecked Sendable {
    public let id: String
    public let agentType: AgentType
    public var model: String?
    public var cwd: String?
    public var status: SessionStatus
    /// Whether this app process has received a live event for the current runtime.
    public var presence: SessionPresence
    /// The persisted status shown as historical context until a fresh runtime event arrives.
    public var lastKnownStatus: SessionStatus?
    public let startedAt: Date
    public var endedAt: Date?
    /// Most recent time a restored or replacement runtime attached to this logical session.
    public var lastResumedAt: Date?
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalCachedTokens: Int
    public var estimatedCost: Double
    public var toolCallCount: Int
    public var currentTool: ToolInfo?
    public var recentTools: [ToolInfo]
    public var pendingInterruptions = PendingInterruptionQueue()
    /// Compatibility projection for list/status callers and tests. Runtime mutation should go
    /// through `pendingInterruptions` so permission/question arrival order stays intact.
    public var pendingPermissions: [PermissionRequest] {
        get { pendingInterruptions.permissions }
        set {
            pendingInterruptions.replacePermissions(with: newValue)
        }
    }
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
    /// True only after the current PID/TTY has been resolved to an activatable terminal app.
    ///
    /// `presence == .restored` is intentionally allowed: an app restart does not make a
    /// still-running terminal unactionable. Restored terminal metadata is cleared and revalidated;
    /// the action stays hidden until that attempt produces a current terminal app name.
    public var isTerminalJumpAvailable: Bool {
        presence != .inactive
            && terminalInfoResolved
            && terminalAppName != nil
            && (pid != nil || tty != nil)
    }
    /// Identifier the Claude desktop app uses for this session (`local_<uuid>`), when the app is the
    /// one running it. nil for terminal sessions and until resolution succeeds.
    public var claudeDesktopSessionId: String?
    /// Whether resolving `claudeDesktopSessionId` was attempted, so a session no desktop record
    /// claims is not looked up again.
    public var claudeDesktopSessionResolved: Bool = false
    /// Session title from transcript (customTitle or slug)
    public var sessionTitle: String?
    /// Whether session title has been resolved from transcript
    public var sessionTitleResolved: Bool = false
    /// First user message; effectively the purpose of the session.
    public var firstUserPrompt: String?
    /// Whether resolving firstUserPrompt has been attempted.
    public var firstUserPromptResolved: Bool = false
    /// Most recent user message (for lastUserMessage).
    public var lastUserPrompt: String?
    /// Final assistant message on completion; set by SessionFinalizer.
    public var lastAssistantMessage: String?
    /// Moment the session became done; the reference point for the completion animation.
    public var doneAt: Date?
    /// The oldest queued question, which may sit behind an earlier permission.
    public var pendingQuestion: PendingQuestion? {
        get { pendingInterruptions.questions.first }
        set {
            pendingInterruptions.replaceFirstQuestion(with: newValue)
        }
    }
    public var currentInterruption: PendingInterruption? { pendingInterruptions.first }
    public var hasPendingInterruptions: Bool { !pendingInterruptions.isEmpty }
    public var lastActivityAt: Date
    /// Current permission mode (`default` / `acceptEdits` / `plan` / `dontAsk` / `bypassPermissions`),
    /// taken from the `permission_mode` field common to all hook events. nil until one arrives.
    public var permissionMode: PermissionMode?
    /// The agent's internal task list, managed via TaskCreate/TaskUpdate.
    public var tasks: [AgentTask] = []

    /// Running and completed subagents, oldest first. Completed runs are capped at 50.
    public var subagents: [SubagentRun] = []
    /// How many subagents were running when the session completed (`foldRunningSubagentsToCompleted`).
    /// Keeps the left wing's swarm display alive while the completion notification is shown (compact UI).
    public var subagentCountAtCompletion: Int = 0
    /// Agent-teams team name, taken from `team_name` on TeammateIdle / TaskCreated / TaskCompleted.
    public var teamName: String?
    /// This session's member name within an agent team, taken from `teammate_name` on TeammateIdle.
    /// nil means the team lead (or not part of a team).
    public var teammateName: String?

    public var runningSubagentCount: Int {
        subagents.filter { $0.status == .running }.count
    }

    /// The status to move to right after handling a response (approve / deny / answer) to a
    /// PermissionRequest or AskUserQuestion.
    /// - Stays at `.permissionWaiting` if any interruption remains.
    /// - Otherwise picks `.subagentRunning` or `.thinking` depending on whether subagents are still running.
    /// Callers must clear the resolved queue item *before* calling this.
    public func statusAfterPermissionResolved() -> SessionStatus {
        if hasPendingInterruptions {
            return .permissionWaiting
        }
        return runningSubagentCount > 0 ? .subagentRunning : .thinking
    }

    /// Cached git metadata resolved asynchronously by `GitInfoResolver.resolve(cwd:)`.
    /// nil until resolved; `EventProcessor.backfillSession` sets it once.
    public var gitInfo: GitInfo?
    /// Whether resolving `gitInfo` was attempted, so a nil result is not retried forever.
    public var gitInfoResolved: Bool = false

    public var elapsedTime: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Resolved branch name; nil if unresolved or not under git.
    public var gitBranch: String? { gitInfo?.branch }

    /// Name of the origin repository when this is a worktree.
    public var originRepoName: String? { gitInfo?.originRepoName }

    /// Worktree name; nil if this is not a worktree.
    public var worktreeName: String? { gitInfo?.worktreeName }

    /// Records a SubagentStart.
    public func startSubagent(agentType: String, agentId: String?, at date: Date = Date()) {
        subagents.append(
            SubagentRun(
                id: agentId ?? UUID().uuidString,
                agentType: agentType,
                startedAt: date,
                hasExplicitId: agentId != nil
            ))
    }

    /// Applies a SubagentStop to the matching run.
    /// Match order: same agentId, then the oldest running run with the same agentType, then the
    /// oldest running run; returns false if none match, which makes duplicate Stops harmless.
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

    /// Folds every running subagent to completed (used when the session ends), recording how many
    /// were running into `subagentCountAtCompletion`.
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

    /// Drops the oldest completed runs to keep the list at 50 entries.
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
        self.presence = .live
        self.lastKnownStatus = nil
        self.startedAt = startedAt
        self.endedAt = nil
        self.lastResumedAt = nil
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.totalCachedTokens = 0
        self.estimatedCost = 0
        self.toolCallCount = 0
        self.currentTool = nil
        self.recentTools = []
        self.pid = nil
        self.tty = nil
        self.transcriptPath = nil
        self.lastActivityAt = startedAt
    }
}
