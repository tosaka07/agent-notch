import AgentNotchCore
import Foundation

/// Runs the Unix socket server and applies incoming messages to `SessionManager`
/// through `EventProcessor`. Also exposes the permission responses
/// (approve/deny/answer) that views call into.
@MainActor
final class SocketCoordinator {
    private let sessionManager: SessionManager
    private let socketPath: String
    private let codexQuestions: CodexQuestionCoordinator?
    private var socketServer: SocketServer?
    /// Holder that lets the onMessage closure reach the `SocketServer` itself.
    /// Owned by the coordinator so it outlives `start()`.
    /// `server` is weak, so there is no retain cycle (the `socketServer` property
    /// holds the strong reference).
    private let serverBox = ServerBox()

    init(
        sessionManager: SessionManager,
        socketPath: String = SocketServer.socketPath,
        codexQuestions: CodexQuestionCoordinator? = nil
    ) {
        self.sessionManager = sessionManager
        self.socketPath = socketPath
        self.codexQuestions = codexQuestions
    }

    func start() {
        let manager = sessionManager
        let serverBox = self.serverBox
        let codexQuestionBox = CodexQuestionBox(codexQuestions)

        do {
            let server = try SocketServer(
                socketPath: socketPath,
                onMessage: { [serverBox, codexQuestionBox] message, connection in
                    // Parse off MainActor — pure data processing
                    let parsed = EventProcessor.parseMessage(message)
                    let hookEvent = message["hook_event_name"] as? String ?? ""
                    // Log every received hook, including unknown ones, so it is possible
                    // to see what actually arrives.
                    let sid = message["session_id"] as? String ?? "?"
                    if case .unknown = parsed.event {
                        Log.socket.info("← [UNKNOWN hook] event=\(hookEvent) session=\(sid)")
                    } else {
                        Log.socket.debug("← hook event=\(hookEvent) session=\(sid)")
                    }
                    let cwd = message["cwd"] as? String
                    let transcriptPath = message["transcript_path"] as? String
                    let pid = (message["_pid"] as? NSNumber)?.int32Value
                    let tty = message["_tty"] as? String
                    let permissionMode = parsed.permissionMode
                    let sessionStartSource = message["source"] as? String
                    let hookToolName = message["tool_name"] as? String ?? ""
                    let hookToolUseId = message["tool_use_id"] as? String ?? ""

                    // Defer only when it came through the `PermissionRequest` hook — the only
                    // path that can inject a tool_response. An AskUserQuestion arriving via
                    // `PreToolUse` must be answered immediately or the agent blocks, and the
                    // answer would not become a tool_response anyway, so it is passed through.
                    let deferred:
                        (
                            kind: PendingSocketResponse.Kind, sessionId: String, toolUseId: String,
                            toolInput: JSONBox?
                        )?
                    switch parsed.event {
                    case .askQuestion(let info) where hookEvent == "PermissionRequest":
                        // Keep the original tool_input (which carries `questions`) so it can be
                        // restored when responding.
                        let rawToolInput = message["tool_input"] as? [String: Any]
                        deferred = (
                            .askUserQuestion, info.sessionId, info.toolUseId, rawToolInput.map(JSONBox.init)
                        )
                    case .permissionRequested(let info):
                        deferred = (.permissionRequest, info.sessionId, info.toolUseId, nil)
                    default:
                        deferred = nil
                    }

                    // For deferred cases, settle the outcome of addPending synchronously and
                    // up front (addPending itself is synchronous and MainActor-independent).
                    // If it fails — i.e. the toolUseId collides with an existing one, which is a
                    // hijack attempt — then letting `apply` add pendingPermissions/pendingQuestion
                    // to the UI would show what looks like a legitimate approval request while the
                    // approve/deny response goes to the attacker's new connection. So skip `apply`
                    // entirely, close the new connection, and return.
                    var pendingRegistered = true
                    if let d = deferred {
                        let pending = PendingSocketResponse(
                            kind: d.kind,
                            sessionId: d.sessionId,
                            toolUseId: d.toolUseId,
                            connection: connection,
                            receivedAt: Date(),
                            toolInput: d.toolInput
                        )
                        pendingRegistered = serverBox.server?.addPending(pending) == true
                        if !pendingRegistered {
                            Log.socket.warning(
                                "Rejected duplicate/hijack-attempt pending toolUseId=\(d.toolUseId); closing new connection"
                            )
                            connection.cancel()
                        } else {
                            Log.socket.info("Deferred \(d.kind.rawValue) toolUseId=\(d.toolUseId)")
                        }
                    }

                    Task { @MainActor in
                        guard pendingRegistered else { return }

                        let accepted = manager.prepareForRuntimeEvent(
                            sessionId: parsed.sessionId,
                            agentType: parsed.agentType,
                            pid: pid,
                            isSessionStart: hookEvent == "SessionStart"
                        )
                        guard accepted else {
                            let pidDescription = pid.map(String.init) ?? "nil"
                            Log.socket.warning(
                                "Ignored event from stale runtime event=\(hookEvent) session=\(parsed.sessionId) pid=\(pidDescription)"
                            )
                            if let deferred {
                                serverBox.server?.cancelPending(toolUseId: deferred.toolUseId)
                            }
                            return
                        }

                        // When the same process (pid) issues a new session_id after resume/compact/
                        // clear, merge the old session into the new one so the list does not split.
                        // Do not merge when `source` is startup (which also covers a teammate
                        // launching a fresh session).
                        // Matching on cwd as well as pid raises the bar for taking over another
                        // session by sending a SessionStart with a spoofed _pid.
                        // SessionStart is never deferred, so pendingRegistered is always true here,
                        // but reconciling before `apply` and outside the guard is fine.
                        if hookEvent == "SessionStart" {
                            manager.reconcileSessionStart(
                                newId: parsed.sessionId, pid: pid, cwd: cwd, source: sessionStartSource
                            )
                        }
                        let isCodexUserInput =
                            parsed.agentType == .codex
                            && hookToolName == "request_user_input"
                        if isCodexUserInput, hookEvent == "PreToolUse",
                            case .askQuestion(let info) = parsed.event,
                            let codexQuestions = codexQuestionBox.coordinator
                        {
                            _ =
                                manager.session(for: parsed.sessionId)
                                ?? manager.getOrCreateSession(
                                    id: parsed.sessionId,
                                    agentType: parsed.agentType
                                )
                            codexQuestions.receiveHookQuestion(info, turnId: parsed.turnId)
                        } else {
                            EventProcessor.apply(
                                parsed.event,
                                agentType: parsed.agentType,
                                manager: manager
                            )
                        }
                        EventProcessor.backfillSession(
                            parsed.sessionId, cwd: cwd, transcriptPath: transcriptPath,
                            pid: pid, tty: tty, manager: manager
                        )
                        if isCodexUserInput,
                            hookEvent == "PostToolUse" || hookEvent == "PostToolUseFailure"
                        {
                            codexQuestionBox.coordinator?.receiveObservedResolution(
                                sessionId: parsed.sessionId,
                                toolUseId: hookToolUseId
                            )
                        }
                        EventProcessor.applyPermissionMode(
                            sessionId: parsed.sessionId, rawMode: permissionMode, manager: manager
                        )
                    }

                    // If not deferred, return an immediate empty response (pass-through).
                    // If deferred, the response is handled elsewhere in both outcomes (deferred
                    // send, or an immediate close), so return nil — no immediate response.
                    guard deferred != nil else { return [String: Any]() }
                    return nil
                },
                onPendingExpired: { pending in
                    // Called on the socket queue. Reflects a pending entry that was abandoned
                    // (the hook left on recv timeout, or the TTL expired) into session state and
                    // switches the banner to its expired presentation.
                    let sessionId = pending.sessionId
                    let toolUseId = pending.toolUseId
                    let kind = pending.kind
                    Task { @MainActor in
                        EventProcessor.applyPendingExpired(
                            sessionId: sessionId, toolUseId: toolUseId, kind: kind, manager: manager
                        )
                    }
                })
            serverBox.server = server
            server.start()
            socketServer = server
        } catch {
            Log.socket.error("Failed to start socket server: \(error)")
        }
    }

    /// Holder that lets the onMessage closure reach the `SocketServer` itself.
    /// `server` is weak; the strong reference lives in `SocketCoordinator.socketServer`,
    /// so there is no retain cycle.
    private final class ServerBox: @unchecked Sendable {
        weak var server: SocketServer?
    }

    /// Crosses the socket queue without treating the MainActor coordinator
    /// itself as Sendable. It is dereferenced only inside a MainActor task.
    private final class CodexQuestionBox: @unchecked Sendable {
        weak var coordinator: CodexQuestionCoordinator?

        init(_ coordinator: CodexQuestionCoordinator?) {
            self.coordinator = coordinator
        }
    }

    func stop() {
        socketServer?.stop()
        socketServer = nil
    }

    // MARK: - Permission actions (exposed to SwiftUI via EnvironmentValues)

    /// Injected into views via `.environment(\.permissionActions, socket.permissionActions)`.
    var permissionActions: PermissionActions {
        PermissionActions(
            approve: { [weak self] sessionId, toolUseId in
                self?.approve(sessionId: sessionId, toolUseId: toolUseId)
            },
            deny: { [weak self] sessionId, toolUseId, reason in
                self?.deny(sessionId: sessionId, toolUseId: toolUseId, reason: reason)
            },
            respondInTerminal: { [weak self] sessionId, toolUseId in
                self?.respondInTerminal(sessionId: sessionId, toolUseId: toolUseId)
            },
            answerQuestion: { [weak self] sessionId, toolUseId, answers in
                self?.answer(sessionId: sessionId, toolUseId: toolUseId, answers: answers)
            },
            dismissExpired: { [weak self] sessionId, toolUseId in
                self?.dismissExpired(sessionId: sessionId, toolUseId: toolUseId)
            }
        )
    }

    private func approve(sessionId: String, toolUseId: String) {
        let delivered =
            socketServer?.respondToPermission(
                toolUseId: toolUseId, decision: "allow", reason: nil
            ) ?? false
        if delivered {
            clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
        } else {
            markPermissionExpired(sessionId: sessionId, toolUseId: toolUseId)
        }
    }

    private func deny(sessionId: String, toolUseId: String, reason: String?) {
        let delivered =
            socketServer?.respondToPermission(
                toolUseId: toolUseId, decision: "deny", reason: reason
            ) ?? false
        if delivered {
            clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
        } else {
            markPermissionExpired(sessionId: sessionId, toolUseId: toolUseId)
        }
    }

    /// Declines to decide in the hook and lets the agent surface its native terminal prompt.
    private func respondInTerminal(sessionId: String, toolUseId: String) {
        let delivered = socketServer?.respondInTerminal(toolUseId: toolUseId) ?? false
        if delivered {
            clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
        } else {
            markPermissionExpired(sessionId: sessionId, toolUseId: toolUseId)
        }
    }

    /// Sends an AskUserQuestion answer in the shape Claude Code expects.
    /// It is injected into `decision.updatedInput.answers` as `{question: answer}`.
    /// Multi-select values are joined with " / " because Claude Code expects a single string.
    /// If the response path has expired, the banner is switched to its expired presentation
    /// rather than dismissed — never make an undelivered answer look delivered.
    private func answer(sessionId: String, toolUseId: String, answers: [String: [String]]) {
        guard let session = sessionManager.session(for: sessionId),
            session.pendingInterruptions.question(toolUseId: toolUseId) != nil
        else {
            // Double submit from a stale view, etc. Do nothing without a matching pendingQuestion.
            Log.socket.warning(
                "answer: no matching pendingQuestion session=\(sessionId) toolUseId=\(toolUseId)")
            return
        }
        if codexQuestions?.canHandle(sessionId: sessionId, toolUseId: toolUseId) == true {
            codexQuestions?.answer(
                sessionId: sessionId,
                toolUseId: toolUseId,
                answers: answers
            )
            return
        }
        let flatAnswers = answers.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = pair.value.joined(separator: " / ")
        }
        let delivered =
            socketServer?.respondToAskQuestion(
                toolUseId: toolUseId, answers: flatAnswers
            ) ?? false
        if delivered {
            session.pendingInterruptions.remove(
                kind: .question, toolUseId: toolUseId)
            // Keep permissionWaiting while other approvals/questions are still pending;
            // otherwise pick the next status from whether a subagent is running rather than
            // hardcoding `.thinking`.
            session.status = session.statusAfterPermissionResolved()
        } else {
            session.pendingInterruptions.updateQuestion(
                toolUseId: toolUseId,
                { $0.isExpired = true }
            )
        }
        sessionManager.notifyChange()
    }

    /// Switches a permission whose response could not be delivered to the expired
    /// presentation (canRespond = false).
    private func markPermissionExpired(sessionId: String, toolUseId: String) {
        EventProcessor.applyPendingExpired(
            sessionId: sessionId, toolUseId: toolUseId, kind: .permissionRequest, manager: sessionManager
        )
    }

    /// Dismisses an expired question/permission banner by user action.
    private func dismissExpired(sessionId: String, toolUseId: String) {
        guard let session = sessionManager.session(for: sessionId) else { return }
        codexQuestions?.dismiss(sessionId: sessionId, toolUseId: toolUseId)
        session.pendingInterruptions.remove(
            kind: .question, toolUseId: toolUseId)
        session.pendingInterruptions.remove(
            kind: .permission, toolUseId: toolUseId)
        session.status = session.statusAfterPermissionResolved()
        sessionManager.notifyChange()
    }

    private func clearPendingPermission(sessionId: String, toolUseId: String) {
        guard let session = sessionManager.session(for: sessionId) else { return }
        session.pendingInterruptions.remove(
            kind: .permission, toolUseId: toolUseId)
        // Keep permissionWaiting while other approvals/questions are still pending;
        // otherwise pick the next status from whether a subagent is running rather than
        // hardcoding `.thinking`.
        session.status = session.statusAfterPermissionResolved()
        sessionManager.notifyChange()
    }
}
