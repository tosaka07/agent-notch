import AgentNotchCore
import Foundation

/// Processes hook events and updates session state.
/// Extracted from AppDelegate for single-responsibility and testability.
enum EventProcessor {
    /// Parse a raw socket message into a typed event and detect the agent type.
    /// Pure data processing — no MainActor needed.
    static func parseMessage(_ message: [String: Any]) -> (event: ClaudeEvent, agentType: AgentType, sessionId: String) {
        let event = ClaudeEventParser.parse(message)
        let sessionId = message["session_id"] as? String ?? ""
        let agentType: AgentType = (message["_agent_type"] as? String) == "codex" ? .codex : .claudeCode
        return (event, agentType, sessionId)
    }

    /// Apply an event to the session manager. Must be called on MainActor.
    @MainActor static func apply(_ event: ClaudeEvent, agentType: AgentType, manager: SessionManager) {
        defer { manager.notifyChange() }

        switch event {
        case let .sessionStarted(info):
            Log.events.info("sessionStarted id=\(info.sessionId) model=\(info.model ?? "?") cwd=\(info.cwd ?? "?")")
            let session = manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.model = info.model
            session.cwd = info.cwd
            session.transcriptPath = info.transcriptPath
            session.status = .idle

        case let .userPrompt(sessionId):
            Log.events.info("userPrompt id=\(sessionId)")
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .thinking
            NotificationCenter.default.post(name: .agentNotchSessionResumed, object: sessionId)

        case let .toolStarted(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.status = .toolRunning
            session.currentTool = ToolInfo(
                id: info.toolUseId, name: info.toolName, summary: info.summary,
                input: info.toolInput, startedAt: Date(), status: .running
            )
            session.toolCallCount += 1

        case let .toolCompleted(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .succeeded
                    tool.completedAt = Date()
                    session.recentTools.insert(tool, at: 0)
                    if session.recentTools.count > 50 { session.recentTools.removeLast() }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .toolFailed(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .failed; tool.completedAt = Date()
                    session.recentTools.insert(tool, at: 0)
                    if session.recentTools.count > 50 { session.recentTools.removeLast() }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .permissionRequested(info):
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

        case let .askQuestion(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.status = .permissionWaiting
            session.pendingQuestion = PendingQuestion(
                toolUseId: info.toolUseId, question: info.question, options: info.options
            )
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)

        case let .notification(sessionId, type, _):
            if type == "idle_prompt" {
                let session = manager.session(for: sessionId)
                    ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
                session.status = .idle
            }

        case let .subagentStarted(sessionId, _):
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .subagentRunning

        case let .stopFailure(sessionId, errorType):
            Log.events.error("stopFailure id=\(sessionId) error=\(errorType)")
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .error
            session.currentTool = nil
            SoundPlayer.play(.error)

        case let .compactingDone(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .thinking
            }

        case let .sessionIdle(sessionId):
            Log.events.info("sessionIdle (done) id=\(sessionId)")
            if let session = manager.session(for: sessionId) {
                session.status = .done
                session.currentTool = nil
                session.pendingPermissions.removeAll()
                session.pendingQuestion = nil

                // Capture values for background parsing
                let path = session.transcriptPath
                let model = session.model
                let projectName = session.originRepoName
                    ?? (session.cwd as NSString?)?.lastPathComponent ?? "Session"
                let gitBranch = session.gitBranch
                let isWorktree = session.worktreeName != nil
                let pid = session.pid
                let tty = session.tty

                // Parse transcript off MainActor (file I/O can be slow for long sessions)
                Task.detached {
                    var inputTokens = 0, outputTokens = 0, cachedTokens = 0
                    var estimatedCost = 0.0
                    var lastMessage = ""

                    if let path, let model {
                        let usage = TranscriptParser.parseCumulativeUsage(at: path)
                        inputTokens = usage.inputTokens
                        outputTokens = usage.outputTokens
                        cachedTokens = usage.cachedTokens
                        estimatedCost = CostCalculator.estimateCost(
                            model: model, inputTokens: inputTokens,
                            outputTokens: outputTokens, cachedTokens: cachedTokens
                        )
                    }
                    if let path {
                        lastMessage = TranscriptParser.lastAssistantMessage(at: path) ?? ""
                    }

                    await MainActor.run {
                        if let s = manager.session(for: sessionId) {
                            s.totalInputTokens = inputTokens
                            s.totalOutputTokens = outputTokens
                            s.totalCachedTokens = cachedTokens
                            s.estimatedCost = estimatedCost
                        }
                        NotificationCenter.default.post(
                            name: .agentNotchSessionCompleted,
                            object: sessionId,
                            userInfo: [
                                "projectName": projectName,
                                "gitBranch": gitBranch as Any,
                                "isWorktree": isWorktree,
                                "message": lastMessage,
                                "pid": pid as Any,
                                "tty": tty as Any,
                            ]
                        )
                        SoundPlayer.play(.sessionCompleted)
                        manager.notifyChange()
                    }
                }
            }

        case let .sessionEnded(sessionId):
            Log.events.info("sessionEnded id=\(sessionId)")
            manager.removeSession(id: sessionId)

        case let .compacting(sessionId):
            manager.session(for: sessionId)?.status = .compacting

        case .subagentStopped, .unknown:
            break
        }
    }

    /// Backfill common fields onto the session.
    @MainActor static func backfillSession(
        _ sessionId: String, cwd: String?, transcriptPath: String?,
        pid: Int32?, tty: String?, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId) else { return }
        session.lastActivityAt = Date()

        if session.cwd == nil, let cwd { session.cwd = cwd }
        if session.transcriptPath == nil, let transcriptPath { session.transcriptPath = transcriptPath }
        if session.pid == nil, let pid { session.pid = pid }
        if session.tty == nil, let tty { session.tty = tty }

        // Resolve terminal info once (off main thread)
        if !session.terminalInfoResolved, (session.pid != nil || session.tty != nil) {
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
    }
}
