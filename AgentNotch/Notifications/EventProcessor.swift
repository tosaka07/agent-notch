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
    static func parseMessage(
        _ message: [String: Any]
    ) -> (event: ClaudeEvent, agentType: AgentType, sessionId: String, permissionMode: String?) {
        let event = ClaudeEventParser.parse(message)
        let sessionId = message["session_id"] as? String ?? ""
        let agentType: AgentType = (message["_agent_type"] as? String) == "codex" ? .codex : .claudeCode
        let permissionMode = ClaudeEventParser.permissionMode(from: message)
        return (event, agentType, sessionId, permissionMode)
    }

    /// `permission_mode` を Session に反映する。session がまだ存在しない場合は何もしない
    /// （SessionStart 等、他の handler が先に session を作る前提のため）。
    @MainActor
    static func applyPermissionMode(sessionId: String, rawMode: String?, manager: SessionManager) {
        guard let rawMode, let mode = PermissionMode(rawValue: rawMode) else { return }
        guard let session = manager.session(for: sessionId), session.permissionMode != mode else { return }
        session.permissionMode = mode
        manager.notifyChange()
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

        case let .subagentStarted(info):
            handleSubagentStarted(info, agentType: agentType, manager: manager)

        case let .subagentStopped(info):
            handleSubagentStopped(info, manager: manager)

        case let .teammateIdle(info):
            handleTeammateIdle(info, manager: manager)

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

        case let .taskCreated(info):
            handleTaskCreated(info, agentType: agentType, manager: manager)

        case let .taskCompleted(info):
            handleTaskCompleted(info, agentType: agentType, manager: manager)

        case let .taskUpdated(sessionId, taskId, status):
            handleTaskUpdated(sessionId: sessionId, taskId: taskId, status: status, manager: manager)

        case .unknown:
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

        // lastUserPrompt を非同期で更新
        // UserPromptSubmit hook は transcript 書き込みより先に飛ぶことがあるため、
        // 少し待ってから読む。
        if let path = session.transcriptPath {
            Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                let prompt = TranscriptParser.lastUserMessage(at: path)
                await MainActor.run {
                    if let s = manager.session(for: sessionId), let prompt {
                        s.lastUserPrompt = prompt
                        manager.notifyChange()
                    }
                }
            }
        }
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
        // Issue #7: PreToolUse で立てた currentTool(.running) をここで消さないと、
        // UI 側の「ツール実行中」表示（currentTool.status == .running を優先するブランチ）が
        // permissionWaiting の表示より先に評価されてしまい、承認待ち（Plan モードの確認含む）が
        // 実行中/Thinking のように見え続けるバグになっていた。承認待ちの間はまだ実行されていないので nil に戻す。
        session.currentTool = nil
        let muted = manager.isMuted(info.sessionId)
        if !muted { SoundPlayer.play(.permissionWaiting) }
        session.pendingPermissions.append(PermissionRequest(
            id: UUID().uuidString, agentType: agentType,
            sessionId: info.sessionId, toolName: info.toolName,
            toolInput: info.toolInput, toolUseId: info.toolUseId,
            timestamp: Date(), canRespond: true
        ))
        if !muted {
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
        }
    }

    @MainActor
    private static func handleAskQuestion(
        _ info: AskQuestionInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.status = .permissionWaiting
        session.pendingQuestion = PendingQuestion(
            toolUseId: info.toolUseId, questions: info.questions
        )
        if !manager.isMuted(info.sessionId) {
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
        }
    }

    @MainActor
    private static func handleNotification(
        sessionId: String, type: String, agentType: AgentType, manager: SessionManager
    ) {
        guard type == "idle_prompt" else { return }
        let session = manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        // Claude Code 2.1 以降、Stop 直後に idle_prompt が飛んできて
        // 完了状態を潰すことがあるので .done は保持する。
        // 次の userPrompt / toolStarted で遷移するまで完了表示を維持。
        if session.status == .done { return }
        session.status = .idle
    }

    @MainActor
    private static func handleSubagentStarted(
        _ info: SubagentStartInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.startSubagent(agentType: info.agentType, agentId: info.agentId)
        session.status = .subagentRunning
        Log.events.info("subagentStarted id=\(info.sessionId) type=\(info.agentType) agentId=\(info.agentId ?? "-")")
    }

    @MainActor
    private static func handleSubagentStopped(_ info: SubagentStopInfo, manager: SessionManager) {
        guard let session = manager.session(for: info.sessionId) else { return }
        let matched = session.stopSubagent(
            agentId: info.agentId, agentType: info.agentType, transcriptPath: info.agentTranscriptPath
        )
        // 並行 subagent が全て終わった時のみ status を戻す。.done / .permissionWaiting は潰さない。
        if session.status == .subagentRunning, session.runningSubagentCount == 0 {
            session.status = .thinking
        }
        Log.events.info("subagentStopped id=\(info.sessionId) agentId=\(info.agentId ?? "-") matched=\(matched)")
    }

    @MainActor
    private static func handleTeammateIdle(_ info: TeammateIdleInfo, manager: SessionManager) {
        SessionFinalizer.finalize(sessionId: info.sessionId, manager: manager)

        if let own = manager.session(for: info.sessionId) {
            own.teamName = own.teamName ?? info.teamName
            own.teammateName = own.teammateName ?? info.teammateName
        }
        if let teammateId = info.teammateSessionId, let teammate = manager.session(for: teammateId) {
            teammate.teamName = teammate.teamName ?? info.teamName
            teammate.teammateName = teammate.teammateName ?? info.teammateName
        }
    }

    @MainActor
    private static func handleTaskCreated(
        _ info: TaskCreatedInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.tasks = AgentTaskReconciler.reconcileCreated(tasks: session.tasks, info: info)
        if let teamName = info.teamName { session.teamName = session.teamName ?? teamName }
        Log.events.info("taskCreated id=\(info.sessionId) subject=\(info.subject)")
    }

    @MainActor
    private static func handleTaskCompleted(
        _ info: TaskCompletedInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session = manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.tasks = AgentTaskReconciler.reconcileCompleted(tasks: session.tasks, info: info)
        if let teamName = info.teamName { session.teamName = session.teamName ?? teamName }
        Log.events.info("taskCompleted id=\(info.sessionId) taskId=\(info.taskId ?? "-") by=\(info.completedBy ?? "-")")
    }

    @MainActor
    private static func handleTaskUpdated(
        sessionId: String, taskId: String, status: String, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId),
              let index = session.tasks.firstIndex(where: { $0.id == taskId })
        else { return }

        if let newStatus = AgentTask.Status(rawValue: status) {
            session.tasks[index].status = newStatus
            Log.events.info("taskUpdated id=\(sessionId) task=#\(taskId) → \(status)")
        }
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
        if !manager.isMuted(sessionId) {
            SoundPlayer.play(.error)
        }
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
        // done 後は lastActivityAt を更新しない（完了アニメーションの開始時刻がリセットされるのを防ぐ）
        if session.status != .done {
            session.lastActivityAt = Date()
        }

        if session.cwd == nil, let cwd { session.cwd = cwd }
        if session.transcriptPath == nil, let transcriptPath { session.transcriptPath = transcriptPath }
        if session.pid == nil, let pid { session.pid = pid }
        if session.tty == nil, let tty { session.tty = tty }

        resolveTerminalInfoIfNeeded(session: session, sessionId: sessionId, manager: manager)
        resolveSessionTitleIfNeeded(session: session, sessionId: sessionId, manager: manager)
        resolveFirstUserPromptIfNeeded(session: session, sessionId: sessionId, manager: manager)
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
    private static func resolveFirstUserPromptIfNeeded(
        session: UnifiedSession, sessionId: String, manager: SessionManager
    ) {
        guard !session.firstUserPromptResolved, let path = session.transcriptPath else { return }
        session.firstUserPromptResolved = true
        Task.detached {
            let (first, last) = TranscriptParser.userMessages(at: path)
            await MainActor.run {
                if let s = manager.session(for: sessionId) {
                    s.firstUserPrompt = first
                    s.lastUserPrompt = last
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
