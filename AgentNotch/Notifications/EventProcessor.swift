import AgentNotchCore
import Foundation

/// Parses messages received over the socket and applies them to session state.
///
/// - `parseMessage(_:)` is pure data processing and needs no MainActor.
/// - `apply(_:agentType:manager:)` is the MainActor window in which sessions are mutated.
///   The switch is broken into individual handlers so each reads on its own.
/// - `backfillSession(...)` fills in the cwd/pid/tty carried alongside a socket message.
/// Return value of `EventProcessor.parseMessage(_:)`.
/// A struct rather than a tuple, so adding a field does not degrade readability at the
/// call sites.
struct ParsedMessage: Sendable {
    let event: ClaudeEvent
    let agentType: AgentType
    let sessionId: String
    let turnId: String?
    let permissionMode: String?
}

enum EventProcessor {
    /// Converts a received message into a type-safe `ClaudeEvent` and determines the agent type.
    static func parseMessage(_ message: [String: Any]) -> ParsedMessage {
        let event = ClaudeEventParser.parse(message)
        let sessionId = message["session_id"] as? String ?? ""
        let agentType: AgentType = (message["_agent_type"] as? String) == "codex" ? .codex : .claudeCode
        let turnId = message["turn_id"] as? String ?? message["turnId"] as? String
        let permissionMode = ClaudeEventParser.permissionMode(from: message)
        return ParsedMessage(
            event: event, agentType: agentType, sessionId: sessionId,
            turnId: turnId, permissionMode: permissionMode
        )
    }

    /// Applies `permission_mode` to the session. Does nothing when the session does not
    /// exist yet — another handler (SessionStart, etc.) is expected to create it first.
    @MainActor
    static func applyPermissionMode(sessionId: String, rawMode: String?, manager: SessionManager) {
        guard let rawMode, let mode = PermissionMode(rawValue: rawMode) else { return }
        guard let session = manager.session(for: sessionId), session.permissionMode != mode else { return }
        session.permissionMode = mode
        manager.notifyChange()
    }

    /// Applies an event to session state. Must be called on the MainActor.
    @MainActor
    static func apply(_ event: ClaudeEvent, agentType: AgentType, manager: SessionManager) {
        defer { manager.notifyChange() }

        switch event {
        case .sessionStarted(let info):
            handleSessionStarted(info, agentType: agentType, manager: manager)

        case .userPrompt(let sessionId, let prompt):
            handleUserPrompt(sessionId: sessionId, prompt: prompt, agentType: agentType, manager: manager)

        case .toolStarted(let info):
            handleToolStarted(info, agentType: agentType, manager: manager)

        case .toolCompleted(let info):
            handleToolCompleted(info, manager: manager)

        case .toolFailed(let info):
            handleToolFailed(info, manager: manager)

        case .permissionRequested(let info):
            handlePermissionRequested(info, agentType: agentType, manager: manager)

        case .askQuestion(let info):
            handleAskQuestion(info, agentType: agentType, manager: manager)

        case .notification(let sessionId, let type, _):
            handleNotification(sessionId: sessionId, type: type, agentType: agentType, manager: manager)

        case .subagentStarted(let info):
            handleSubagentStarted(info, agentType: agentType, manager: manager)

        case .subagentStopped(let info):
            handleSubagentStopped(info, manager: manager)

        case .teammateIdle(let info):
            handleTeammateIdle(info, manager: manager)

        case .stopFailure(let sessionId, let errorType, let details):
            handleStopFailure(
                sessionId: sessionId, errorType: errorType, details: details,
                agentType: agentType, manager: manager)

        case .compactingDone(let sessionId):
            if let session = manager.session(for: sessionId) {
                setStatusUnlessPermissionPending(session, .thinking)
            }

        case .sessionIdle(let info):
            handleSessionIdle(info, agentType: agentType, manager: manager)

        case .sessionEnded(let sessionId):
            Log.events.info("sessionEnded id=\(sessionId)")
            manager.removeSession(id: sessionId)

        case .compacting(let sessionId):
            if let session = manager.session(for: sessionId) {
                setStatusUnlessPermissionPending(session, .compacting)
            }

        case .taskCreated(let info):
            handleTaskCreated(info, agentType: agentType, manager: manager)

        case .taskCompleted(let info):
            handleTaskCompleted(info, agentType: agentType, manager: manager)

        case .taskUpdated(let sessionId, let taskId, let status):
            handleTaskUpdated(sessionId: sessionId, taskId: taskId, status: status, manager: manager)

        case .taskListReplaced(let info):
            handleTaskListReplaced(info, agentType: agentType, manager: manager)

        case .unknown:
            break
        }
    }

    // MARK: - Individual handlers

    /// Shared guard for the rule that `.permissionWaiting` must stay visible while
    /// the interruption queue is non-empty. With subagents running in
    /// parallel, a PreToolUse/PostToolUse/SubagentStart from a *different* subagent shares
    /// the same session_id and would otherwise overwrite the status, clearing the
    /// waiting-for-approval badge by mistake.
    @MainActor
    private static func setStatusUnlessPermissionPending(_ session: UnifiedSession, _ status: SessionStatus) {
        guard !session.hasPendingInterruptions else { return }
        session.status = status
    }

    @MainActor
    private static func handleSessionStarted(
        _ info: SessionInfo, agentType: AgentType, manager: SessionManager
    ) {
        Log.events.info(
            "sessionStarted id=\(info.sessionId) model=\(info.model ?? "?") cwd=\(info.cwd ?? "?")")
        let session = manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.model = info.model
        session.cwd = info.cwd
        session.transcriptPath = info.transcriptPath
        session.status = .idle
    }

    @MainActor
    private static func handleUserPrompt(
        sessionId: String, prompt: String?, agentType: AgentType, manager: SessionManager
    ) {
        Log.events.info("userPrompt id=\(sessionId)")
        let session =
            manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        setStatusUnlessPermissionPending(session, .thinking)
        NotificationCenter.default.post(name: .agentNotchSessionResumed, object: sessionId)

        // If the UserPromptSubmit hook payload carries the prompt, use it directly. That
        // avoids waiting on the transcript write (sleep + re-read) and the risk of picking
        // up stale content.
        if let prompt, let sanitized = TranscriptParser.sanitizeUserPromptText(prompt) {
            session.lastUserPrompt = sanitized
            // firstUserPrompt is otherwise only filled by transcript backfill, which needs
            // Claude's format — so for Codex, whose transcript cannot be read, no prompt
            // would appear on the list card at all. Fill it from the payload too, without
            // overwriting an existing value.
            if session.firstUserPrompt == nil {
                session.firstUserPrompt = sanitized
            }
            return
        }

        // Fallback: read from the transcript when the payload has no prompt.
        // The UserPromptSubmit hook can fire *before* the transcript write. Pause briefly
        // so the write has started, then wait for the appends to settle —
        // `waitUntilSettled` only watches size changes, so on its own it cannot wait for a
        // write that has not begun.
        if let path = session.transcriptPath {
            Task.detached {
                await TranscriptParser.waitUntilSettled(at: path, minimumWait: .milliseconds(300))
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
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        // Guard against a PreToolUse from another subagent running in parallel clearing
        // the permissionWaiting badge by mistake.
        setStatusUnlessPermissionPending(session, .toolRunning)
        session.currentTool = ToolInfo(
            id: info.toolUseId, name: info.toolName, summary: info.summary,
            input: info.toolInput, startedAt: Date(), status: .running
        )
        session.toolCallCount += 1
    }

    @MainActor
    private static func handleToolCompleted(_ info: ToolEndInfo, manager: SessionManager) {
        clearPendingIfResolvedElsewhere(
            sessionId: info.sessionId, toolName: info.toolName,
            toolUseId: info.toolUseId, manager: manager
        )
        finalizeCurrentTool(
            sessionId: info.sessionId, toolUseId: info.toolUseId, status: .succeeded, manager: manager)
    }

    @MainActor
    private static func handleToolFailed(_ info: ToolFailInfo, manager: SessionManager) {
        clearPendingIfResolvedElsewhere(
            sessionId: info.sessionId, toolName: info.toolName,
            toolUseId: info.toolUseId, manager: manager
        )
        finalizeCurrentTool(
            sessionId: info.sessionId, toolUseId: info.toolUseId, status: .failed, manager: manager)
    }

    /// A PostToolUse / PostToolUseFailure means the tool **already ran**, so the approval
    /// or question was settled somewhere — possibly outside the notch, e.g. in the
    /// terminal. Any remaining pending entry is stale and gets dropped.
    ///
    /// Without this, answering in the terminal leaves the banner and the list's Approve
    /// button in place; pressing them delivers nothing, so the answer silently never sends.
    /// When answered through the notch, answer() / clearPendingPermission() has already
    /// cleared it, making this a no-op.
    ///
    /// When the PermissionRequest carried a real tool invocation ID, completion must match
    /// that exact ID. A tool name alone is not unique while agents run in parallel. Claude
    /// Code currently omits the ID from PermissionRequest, so only that legacy route falls
    /// back to its historical tool-name correlation.
    @MainActor
    private static func clearPendingIfResolvedElsewhere(
        sessionId: String, toolName: String, toolUseId: String, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId) else { return }
        var changed = false

        if toolName == "AskUserQuestion", let question = session.pendingQuestion {
            Log.events.info("pendingQuestion cleared: AskUserQuestion resolved outside notch id=\(sessionId)")
            let resolvedToolUseId =
                session.pendingInterruptions.question(toolUseId: toolUseId)?.toolUseId
                ?? question.toolUseId
            session.pendingInterruptions.remove(
                kind: .question, toolUseId: resolvedToolUseId)
            changed = true
        }

        // Same reasoning for approvals: once the tool has run, nothing is waiting on them.
        // The socket's expiry detection (EOF / TTL) assumes the hook disconnects, so when
        // Claude Code settles it through another path this can go unnoticed for up to
        // 130 seconds, leaving a dead Approve button in the list the whole time. Treat tool
        // completion as the signal that it was settled.
        let isResolvedPermission: (PermissionRequest) -> Bool = { permission in
            guard permission.toolName == toolName else { return false }
            if let invocationId = permission.toolInvocationId {
                return invocationId == toolUseId
            }
            return permission.agentType == .claudeCode
        }
        let staleCount = session.pendingInterruptions.removeAll { interruption in
            guard case .permission(let permission) = interruption else { return false }
            return isResolvedPermission(permission)
        }
        if staleCount > 0 {
            Log.events.info(
                "pendingPermissions cleared: \(toolName) \(toolUseId) resolved outside notch id=\(sessionId) count=\(staleCount)"
            )
            changed = true
        }

        if changed {
            session.status = session.statusAfterPermissionResolved()
        }
    }

    /// Applies a socket-side pending expiry (the hook left on recv timeout, or the TTL
    /// dropped it) to session state. Switches the banner to its expired presentation so
    /// the failure is visible rather than silent, prompting the user to answer in the
    /// terminal instead.
    @MainActor
    static func applyPendingExpired(
        sessionId: String, toolUseId: String, kind: PendingSocketResponse.Kind, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId) else { return }
        switch kind {
        case .askUserQuestion:
            guard
                session.pendingInterruptions.updateQuestion(
                    toolUseId: toolUseId,
                    { $0.isExpired = true }
                )
            else { return }
        case .permissionRequest:
            guard
                session.pendingInterruptions.updatePermission(
                    toolUseId: toolUseId,
                    { old in
                        PermissionRequest(
                            id: old.id, agentType: old.agentType, sessionId: old.sessionId,
                            toolName: old.toolName, toolInput: old.toolInput,
                            toolUseId: old.toolUseId, timestamp: old.timestamp,
                            canRespond: false, toolInvocationId: old.toolInvocationId
                        )
                    }
                )
            else { return }
        }
        Log.events.info("pending expired kind=\(kind.rawValue) session=\(sessionId) toolUseId=\(toolUseId)")
        manager.notifyChange()
    }

    /// Shared logic that closes the running tool as `.succeeded` / `.failed` and pushes it
    /// onto recentTools.
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
        setStatusUnlessPermissionPending(session, .thinking)
    }

    @MainActor
    private static func handlePermissionRequested(
        _ info: PermissionInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.status = .permissionWaiting
        // Clear the currentTool(.running) that PreToolUse set. The UI's "tool running"
        // branch (which prioritizes currentTool.status == .running) is evaluated before the
        // permissionWaiting presentation, so leaving it set makes a pending approval —
        // including Plan mode confirmation — look like it is still running or thinking.
        // Nothing has run yet while waiting for approval, so reset it to nil.
        session.currentTool = nil
        let inserted = session.pendingInterruptions.enqueue(
            PermissionRequest(
                id: UUID().uuidString, agentType: agentType,
                sessionId: info.sessionId, toolName: info.toolName,
                toolInput: info.toolInput, toolUseId: info.toolUseId,
                // Claude Code and Codex both keep PermissionRequest hooks open and accept
                // allow/deny on stdout. Gemini/custom events remain observe-only.
                timestamp: Date(), canRespond: agentType == .claudeCode || agentType == .codex,
                toolInvocationId: info.toolInvocationId
            ))
        let muted = manager.isMuted(info.sessionId)
        if inserted, !muted {
            SoundPlayer.play(.permissionWaiting)
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
        }
    }

    @MainActor
    private static func handleAskQuestion(
        _ info: AskQuestionInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.status = .permissionWaiting
        // Claude can report the same AskUserQuestion through both PreToolUse and
        // PermissionRequest. Replace that transport observation in place; genuinely
        // different questions append behind the card already being answered.
        let inserted = session.pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: info.toolUseId, questions: info.questions),
            coalesceMatchingContent: info.delivery == .responseChannel
        )
        if inserted, !manager.isMuted(info.sessionId) {
            SoundPlayer.play(.question)
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
        }
    }

    @MainActor
    private static func handleNotification(
        sessionId: String, type: String, agentType: AgentType, manager: SessionManager
    ) {
        guard type == "idle_prompt" else { return }
        let session =
            manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
        // Since Claude Code 2.1, an idle_prompt can arrive right after Stop and clobber
        // the completed state, so .done is preserved. The completion presentation stays
        // until the next userPrompt / toolStarted moves it along.
        if session.status == .done { return }
        setStatusUnlessPermissionPending(session, .idle)
    }

    @MainActor
    private static func handleSessionIdle(
        _ info: SessionStopInfo, agentType: AgentType, manager: SessionManager
    ) {
        guard let session = manager.session(for: info.sessionId) else { return }

        // A Stop emitted inside a Claude child agent is not the root session reaching
        // its input prompt. Keep the parent in its aggregate agent state.
        if info.agentId != nil {
            let status: SessionStatus =
                session.runningSubagentCount > 0 ? .subagentRunning : .thinking
            setStatusUnlessPermissionPending(session, status)
            Log.events.debug("Stop ignored for child agent id=\(info.sessionId)")
            return
        }

        // Older Codex hook payloads do not expose root/subagent identity. Rollout
        // session_meta does, so suppress a child thread's Stop using that local marker.
        let transcriptPath = info.transcriptPath ?? session.transcriptPath
        if agentType == .codex,
            let transcriptPath,
            CodexTranscriptReader.isSubagentRollout(path: transcriptPath)
        {
            setStatusUnlessPermissionPending(session, .idle)
            Log.events.debug("Stop ignored for Codex child rollout id=\(info.sessionId)")
            return
        }

        // Claude's payload is authoritative when present. The tracked run count is also
        // required: socket delivery can put Stop a few seconds before SubagentStop.
        // Only agent work and scheduled wake-ups defer completion — a backgrounded shell
        // command leaves the session at the user's input prompt (see `hasPendingWork`).
        if info.hasPendingWork || session.runningSubagentCount > 0 {
            let status: SessionStatus =
                session.runningSubagentCount > 0 ? .subagentRunning : .thinking
            setStatusUnlessPermissionPending(session, status)
            Log.events.info(
                "Stop deferred id=\(info.sessionId) background=\(info.agentBackgroundTaskCount)/\(info.backgroundTaskCount) crons=\(info.sessionCronCount) subagents=\(session.runningSubagentCount)"
            )
            return
        }

        SessionFinalizer.finalize(
            sessionId: info.sessionId, manager: manager,
            payloadLastMessage: info.lastAssistantMessage
        )
    }

    @MainActor
    private static func handleSubagentStarted(
        _ info: SubagentStartInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.startSubagent(agentType: info.agentType, agentId: info.agentId)
        setStatusUnlessPermissionPending(session, .subagentRunning)
        Log.events.info(
            "subagentStarted id=\(info.sessionId) type=\(info.agentType) agentId=\(info.agentId ?? "-")")
    }

    @MainActor
    private static func handleSubagentStopped(_ info: SubagentStopInfo, manager: SessionManager) {
        guard let session = manager.session(for: info.sessionId) else { return }
        let matched = session.stopSubagent(
            agentId: info.agentId, agentType: info.agentType, transcriptPath: info.agentTranscriptPath
        )
        // Only restore the status once every parallel subagent has finished, and never
        // clobber .done / .permissionWaiting.
        if session.status == .subagentRunning, session.runningSubagentCount == 0 {
            session.status = .thinking
        }
        // A finished subagent gets its own sound, distinguishable from task completion
        // (sessionCompleted).
        if matched, !manager.isMuted(info.sessionId) {
            SoundPlayer.play(.subagentCompleted)
        }
        Log.events.info(
            "subagentStopped id=\(info.sessionId) agentId=\(info.agentId ?? "-") matched=\(matched)")
    }

    @MainActor
    private static func handleTeammateIdle(_ info: TeammateIdleInfo, manager: SessionManager) {
        // TeammateIdle is one team member reaching idle, not the root turn reaching the
        // user's input prompt. It only enriches team metadata; the root Stop decides
        // completion after background_tasks and every tracked subagent have settled.
        if let own = manager.session(for: info.sessionId) {
            own.teamName = own.teamName ?? info.teamName
            // Older payloads can point at a teammate explicitly while carrying the
            // leader's session_id. Do not accidentally turn that leader into a member.
            if info.teammateSessionId == nil || info.teammateSessionId == info.sessionId {
                own.teammateName = own.teammateName ?? info.teammateName
            }
        }
        if let teammateId = info.teammateSessionId, let teammate = manager.session(for: teammateId) {
            teammate.teamName = teammate.teamName ?? info.teamName
            teammate.teammateName = teammate.teammateName ?? info.teammateName
        }
        Log.events.info(
            "teammateIdle id=\(info.sessionId) teammate=\(info.teammateName ?? "-")"
        )
    }

    @MainActor
    private static func handleTaskCreated(
        _ info: TaskCreatedInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.tasks = AgentTaskReconciler.reconcileCreated(tasks: session.tasks, info: info)
        if let teamName = info.teamName { session.teamName = session.teamName ?? teamName }
        Log.events.info("taskCreated id=\(info.sessionId) subject=\(info.subject)")
    }

    @MainActor
    private static func handleTaskCompleted(
        _ info: TaskCompletedInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.tasks = AgentTaskReconciler.reconcileCompleted(tasks: session.tasks, info: info)
        if let teamName = info.teamName { session.teamName = session.teamName ?? teamName }
        Log.events.info(
            "taskCompleted id=\(info.sessionId) taskId=\(info.taskId ?? "-") by=\(info.completedBy ?? "-")")
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
    private static func handleTaskListReplaced(
        _ info: TaskListSnapshotInfo, agentType: AgentType, manager: SessionManager
    ) {
        let session =
            manager.session(for: info.sessionId)
            ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
        session.tasks = AgentTaskReconciler.replaceSnapshot(
            tasks: session.tasks,
            items: info.items
        )
        let completed = session.tasks.filter { $0.status == .completed }.count
        Log.events.info(
            "taskListReplaced id=\(info.sessionId) completed=\(completed) total=\(session.tasks.count)")
    }

    /// How long a `StopFailure` is held before it is shown as an error.
    ///
    /// Claude Code recovers from some of the failures it reports here. The one that prompted this:
    /// a request whose prompt had grown past the context window fails, `StopFailure` fires, and
    /// Claude Code then auto-compacts and retries — the user's work carries on. Marking the session
    /// red (and playing the error sound) for that is a false alarm; `.error` means "the work
    /// stopped", per the glyph legend.
    ///
    /// So the failure is provisional until the session goes quiet. Anything arriving in this window
    /// — PreCompact, the retried tool call, a new prompt — is proof of recovery and drops it.
    /// A genuinely fatal failure (rate_limit, billing_error, …) is followed by nothing, so it
    /// surfaces this much later, which no one perceives on a notch.
    @MainActor
    static var stopFailureGrace: Duration = .milliseconds(2500)

    @MainActor
    private static func handleStopFailure(
        sessionId: String, errorType: String, details: String?, agentType: AgentType,
        manager: SessionManager
    ) {
        Log.events.error(
            "stopFailure id=\(sessionId) error=\(errorType) details=\(details ?? "-") (held)"
        )
        let session =
            manager.session(for: sessionId)
            ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)

        // Captured now, before anything else can run: the state the session was in when the
        // failure was reported.
        let statusBefore = session.status

        Task { @MainActor in
            // Captured once the current MainActor turn has finished, so this message's own
            // `backfillSession` timestamp is already included. It moves only for a *later* event.
            let activityBefore = session.lastActivityAt
            try? await Task.sleep(for: stopFailureGrace)

            guard let current = manager.session(for: sessionId), current === session else { return }
            // Either signal is enough to call it recovered. The status catches a state change
            // that lands in the same turn as the failure; the timestamp catches a later event
            // that happens to leave the status where it was (a second tool call, say).
            guard current.status == statusBefore, current.lastActivityAt == activityBefore else {
                Log.events.info("stopFailure recovered id=\(sessionId) error=\(errorType)")
                return
            }

            current.status = .error
            current.currentTool = nil
            manager.notifyChange()
            if !manager.isMuted(sessionId) {
                SoundPlayer.play(.error)
            }
        }
    }

    // MARK: - Backfill (fill the session with metadata carried alongside socket messages)

    /// Applies the cwd / transcriptPath / pid / tty carried alongside a socket message to
    /// the session, and — on the first message only — resolves terminal info and the
    /// session title in the background.
    @MainActor
    static func backfillSession(
        _ sessionId: String, cwd: String?, transcriptPath: String?,
        pid: Int32?, tty: String?, manager: SessionManager
    ) {
        guard let session = manager.session(for: sessionId) else { return }
        // Do not touch lastActivityAt after done, which would reset the completion
        // animation's start time.
        if session.status != .done {
            session.lastActivityAt = Date()
        }

        if let cwd, session.cwd != cwd {
            session.cwd = cwd
            session.gitInfo = nil
            session.gitInfoResolved = false
        }
        if let transcriptPath, session.transcriptPath != transcriptPath {
            session.transcriptPath = transcriptPath
            session.sessionTitleResolved = false
            session.firstUserPromptResolved = false
        }
        // SessionManager has already rejected stale-runtime events. These values therefore
        // belong to the accepted runtime and may replace metadata restored from disk.
        if let pid { session.pid = pid }
        if let tty, session.tty != tty {
            session.tty = tty
            session.terminalInfoResolved = false
        }

        TerminalInfoResolver.resolveIfNeeded(
            session: session,
            sessionId: sessionId,
            manager: manager
        )
        ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: sessionId,
            manager: manager
        )
        resolveSessionTitleIfNeeded(session: session, sessionId: sessionId, manager: manager)
        resolveFirstUserPromptIfNeeded(session: session, sessionId: sessionId, manager: manager)
        resolveGitInfoIfNeeded(session: session, sessionId: sessionId, manager: manager)
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
                if let s = manager.session(for: sessionId), s.transcriptPath == path {
                    s.sessionTitle = title
                    manager.notifyChange()
                }
            }
        }
    }

    @MainActor
    /// Picks up the first/last user message from the transcript, for sessions that were
    /// already running before the app launched.
    ///
    /// **Must not overwrite the lastUserPrompt the hook delivered.** This is an async file
    /// read and can land after the newer prompt carried by `UserPromptSubmit`. Assigning
    /// unconditionally would overwrite a resumed session's card with the **previous**
    /// message still sitting in the transcript.
    ///
    /// **firstUserPrompt, by contrast, is authoritative from the transcript.** The
    /// session's first message is by definition the head of the transcript, which is more
    /// accurate than the payload-derived value (the newest message at the time it
    /// arrived). Overwrite only when the read succeeds — Codex transcripts are not in
    /// Claude's format and cannot be read, so the payload value stays.
    private static func resolveFirstUserPromptIfNeeded(
        session: UnifiedSession, sessionId: String, manager: SessionManager
    ) {
        guard !session.firstUserPromptResolved, let path = session.transcriptPath else { return }
        session.firstUserPromptResolved = true
        Task.detached {
            let (first, last) = TranscriptParser.userMessages(at: path)
            await MainActor.run {
                guard let s = manager.session(for: sessionId), s.transcriptPath == path else { return }
                if let first { s.firstUserPrompt = first }
                if s.lastUserPrompt == nil { s.lastUserPrompt = last }
                manager.notifyChange()
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
                if let s = manager.session(for: sessionId), s.cwd == cwd {
                    s.gitInfo = info
                    manager.notifyChange()
                }
            }
        }
    }
}
