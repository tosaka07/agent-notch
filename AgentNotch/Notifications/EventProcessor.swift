import AgentNotchCore
import Foundation

/// Socket 受信メッセージを parse し、Session 状態に反映する。
///
/// - `parseMessage(_:)` は純データ処理で MainActor 不要。
/// - `apply(_:agentType:manager:)` は MainActor で Session を mutate する window。
///   switch は個別 handler に分解されており、各 handler が独立して読める。
/// - `backfillSession(...)` は socket メッセージに付随する cwd/pid/tty 情報で Session を埋める。
enum EventProcessor {
    /// 受信メッセージを type-safe な `ClaudeEvent` に変換し、agent type も判定する。
    static func parseMessage(_ message: [String: Any]) -> (event: ClaudeEvent, agentType: AgentType, sessionId: String) {
        let event = ClaudeEventParser.parse(message)
        let sessionId = message["session_id"] as? String ?? ""
        let agentType: AgentType = (message["_agent_type"] as? String) == "codex" ? .codex : .claudeCode
        return (event, agentType, sessionId)
    }

    /// イベントを Session 状態に反映する。必ず MainActor で呼ぶこと。
    @MainActor
    static func apply(_ event: ClaudeEvent, agentType: AgentType, manager: SessionManager) {
        defer { manager.notifyChange() }

        switch event {
        case let .sessionStarted(info):
            handleSessionStarted(info, agentType: agentType, manager: manager)

        case let .userPrompt(sessionId):
            handleUserPrompt(sessionId: sessionId, agentType: agentType, manager: manager)

        case let .toolStarted(info):
            handleToolStarted(info, agentType: agentType, manager: manager)

        case let .toolCompleted(info):
            handleToolCompleted(info, manager: manager)

        case let .toolFailed(info):
            handleToolFailed(info, manager: manager)

        case let .permissionRequested(info):
            handlePermissionRequested(info, agentType: agentType, manager: manager)

        case let .askQuestion(info):
            handleAskQuestion(info, agentType: agentType, manager: manager)

        case let .notification(sessionId, type, _):
            handleNotification(sessionId: sessionId, type: type, agentType: agentType, manager: manager)

        case let .subagentStarted(sessionId, _):
            handleSubagentStarted(sessionId: sessionId, agentType: agentType, manager: manager)

        case let .stopFailure(sessionId, errorType):
            handleStopFailure(sessionId: sessionId, errorType: errorType, agentType: agentType, manager: manager)

        case let .compactingDone(sessionId):
            manager.session(for: sessionId)?.status = .thinking

        case let .sessionIdle(sessionId):
            SessionFinalizer.finalize(sessionId: sessionId, manager: manager)

        case let .sessionEnded(sessionId):
            Log.events.info("sessionEnded id=\(sessionId)")
            manager.removeSession(id: sessionId)

        case let .compacting(sessionId):
            manager.session(for: sessionId)?.status = .compacting

        case .subagentStopped, .unknown:
            break
        }
    }

    // MARK: - Individual handlers

    @MainActor
    private static func handleSessionStarted(
        _ info: SessionInfo, agentType: AgentType, manager: SessionManager
    ) {
        Log.events.info("sessionStarted id=\(info.sessionId) model=\(info.model ?? "?") cwd=\(info.cwd ?? "?")")
        let session = manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.model = info.model
        session.cwd = info.cwd
        session.transcriptPath = info.transcriptPath
        session.status = .idle
    }

    @MainActor
    private static func handleUserPrompt(
        sessionId: String, agentType: AgentType, manager: SessionManager
    ) {
        Log.events.info("userPrompt id=\(sessionId)")
        let session = manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        session.status = .thinking
        NotificationCenter.default.post(name: .agentNotchSessionResumed, object: sessionId)
    }

    @MainActor
    private static func handleToolStarted(
        _ info: ToolStartInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.status = .toolRunning
        session.currentTool = ToolInfo(
            id: info.toolUseId, name: info.toolName, summary: info.summary,
            input: info.toolInput, startedAt: Date(), status: .running
        )
        session.toolCallCount += 1
    }

    @MainActor
    private static func handleToolCompleted(_ info: ToolEndInfo, manager: SessionManager) {
        finalizeCurrentTool(sessionId: info.sessionId, toolUseId: info.toolUseId, status: .succeeded, manager: manager)
    }

    @MainActor
    private static func handleToolFailed(_ info: ToolFailInfo, manager: SessionManager) {
        finalizeCurrentTool(sessionId: info.sessionId, toolUseId: info.toolUseId, status: .failed, manager: manager)
    }

    /// 現在実行中のツールを `.succeeded` / `.failed` で閉じて recentTools に積む共通ロジック。
    @MainActor
    private static func finalizeCurrentTool(
        sessionId: String, toolUseId: String, status: ToolInfo.ToolStatus, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId) else { return }
        if var tool = session.currentTool, tool.id == toolUseId {
            tool.status = status
            tool.completedAt = Date()
            session.recentTools.insert(tool, at: 0)
            if session.recentTools.count > 50 { session.recentTools.removeLast() }
        }
        session.currentTool = nil
        session.status = .thinking
    }

    @MainActor
    private static func handlePermissionRequested(
        _ info: PermissionInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.status = .permissionWaiting
        SoundPlayer.play(.permissionWaiting)
        session.pendingPermissions.append(PermissionRequest(
            id: UUID().uuidString, agentType: agentType,
            sessionId: info.sessionId, toolName: info.toolName,
            toolInput: info.toolInput, toolUseId: info.toolUseId,
            timestamp: Date(), canRespond: true
        ))
        NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
    }

    @MainActor
    private static func handleAskQuestion(
        _ info: AskQuestionInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.status = .permissionWaiting
        session.pendingQuestion = PendingQuestion(
            toolUseId: info.toolUseId, question: info.question, options: info.options
        )
        NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
    }

    @MainActor
    private static func handleNotification(
        sessionId: String, type: String, agentType: AgentType, manager: SessionManager
    ) {
        guard type == "idle_prompt" else { return }
        let session = manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        session.status = .idle
    }

    @MainActor
    private static func handleSubagentStarted(
        sessionId: String, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        session.status = .subagentRunning
    }

    @MainActor
    private static func handleStopFailure(
        sessionId: String, errorType: String, agentType: AgentType, manager: SessionManager
    ) {
        Log.events.error("stopFailure id=\(sessionId) error=\(errorType)")
        let session = manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        session.status = .error
        session.currentTool = nil
        SoundPlayer.play(.error)
    }

    // MARK: - Backfill (socket メッセージに付随するメタ情報を Session に埋める)

    /// socket メッセージに付随する cwd / transcriptPath / pid / tty 情報を Session に反映。
    /// 合わせて、初回のみ terminal info と session title を background で解決する。
    @MainActor
    static func backfillSession(
        _ sessionId: String, cwd: String?, transcriptPath: String?,
        pid: Int32?, tty: String?, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId) else { return }
        session.lastActivityAt = Date()

        if session.cwd == nil, let cwd { session.cwd = cwd }
        if session.transcriptPath == nil, let transcriptPath { session.transcriptPath = transcriptPath }
        if session.pid == nil, let pid { session.pid = pid }
        if session.tty == nil, let tty { session.tty = tty }

        resolveTerminalInfoIfNeeded(session: session, sessionId: sessionId, manager: manager)
        resolveSessionTitleIfNeeded(session: session, sessionId: sessionId, manager: manager)
        resolveGitInfoIfNeeded(session: session, sessionId: sessionId, manager: manager)
    }

    @MainActor
    private static func resolveTerminalInfoIfNeeded(
        session: UnifiedSession, sessionId: String, manager: SessionManager
    ) {
        guard !session.terminalInfoResolved, session.pid != nil || session.tty != nil else { return }
        session.terminalInfoResolved = true
        let sPid = session.pid
        let sTty = session.tty
        Task.detached {
            let info = await TerminalJumper.resolveTerminalInfo(pid: sPid, tty: sTty)
            await MainActor.run {
                if let s = manager.session(for: sessionId) {
                    s.terminalAppName = info?.appName
                    s.terminalAppIcon = info?.appIcon
                    s.tmuxPaneTarget = info?.tmuxTarget
                    manager.notifyChange()
                }
            }
        }
    }

    @MainActor
    private static func resolveSessionTitleIfNeeded(
        session: UnifiedSession, sessionId: String, manager: SessionManager
    ) {
        guard !session.sessionTitleResolved, let path = session.transcriptPath else { return }
        session.sessionTitleResolved = true
        Task.detached {
            let title = TranscriptParser.sessionTitle(at: path)
            await MainActor.run {
                if let s = manager.session(for: sessionId) {
                    s.sessionTitle = title
                    manager.notifyChange()
                }
            }
        }
    }

    @MainActor
    private static func resolveGitInfoIfNeeded(
        session: UnifiedSession, sessionId: String, manager: SessionManager
    ) {
        guard !session.gitInfoResolved, let cwd = session.cwd else { return }
        session.gitInfoResolved = true
        Task.detached {
            let info = GitInfoResolver.resolve(cwd: cwd)
            await MainActor.run {
                if let s = manager.session(for: sessionId) {
                    s.gitInfo = info
                    manager.notifyChange()
                }
            }
        }
    }
}
