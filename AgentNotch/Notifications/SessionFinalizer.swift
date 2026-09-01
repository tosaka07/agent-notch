import AgentNotchCore
import Foundation

/// Handles the heavyweight part of the `.sessionIdle` (session finished) event.
///
/// Moves the session to done, then parses the transcript in the background to settle
/// tokens and cost, and posts the completion notification (`.agentNotchSessionCompleted`).
///
/// The I/O is heavy, so it always runs in `Task.detached`.
@MainActor
enum SessionFinalizer {
    /// Marks the session as finished, then loads the transcript asynchronously and
    /// applies the result to the UI.
    /// - Parameter payloadLastMessage: The final response text carried on the Stop hook
    ///   payload (Codex's `last_assistant_message`). Preferred over parsing the transcript
    ///   when present, and the only source for Codex, whose transcript is not in Claude's
    ///   format and cannot be read.
    static func finalize(
        sessionId: String,
        manager: SessionManager,
        payloadLastMessage: String? = nil
    ) {
        guard let session = manager.session(for: sessionId) else { return }

        // Completion is a root user-input boundary. EventProcessor normally enforces
        // this before calling finalize; keep the invariant here too so a future caller
        // cannot fold active agents away and show a premature checkmark.
        guard session.runningSubagentCount == 0 else {
            Log.events.debug(
                "finalize skipped (subagents still running) id=\(sessionId) count=\(session.runningSubagentCount)"
            )
            return
        }

        // Re-entrancy guard: duplicate Stop events must not fire the completion
        // notification or sound twice, or reset the completion animation's reference
        // time.
        // The next turn's UserPromptSubmit puts the status back to .thinking, so a
        // legitimate later finalize still gets through.
        guard session.status != .done else {
            Log.events.debug("finalize skipped (already done) id=\(sessionId)")
            return
        }

        Log.events.info("sessionIdle (done) id=\(sessionId)")

        session.status = .done
        session.doneAt = Date()
        session.deferredStopAt = nil
        session.currentTool = nil
        session.pendingInterruptions.removeAll()
        session.foldRunningSubagentsToCompleted()
        let finalizedAt = session.doneAt

        // Snapshot the values on the MainActor for the async work below.
        let transcriptPath = session.transcriptPath
        let model = session.model
        let projectName =
            session.originRepoName
            ?? (session.cwd as NSString?)?.lastPathComponent ?? "Session"
        let sessionTitle = session.sessionTitle
        let gitBranch = session.gitBranch
        let isWorktree = session.worktreeName != nil
        let pid = session.pid
        let tty = session.tty
        let muted = manager.isMuted(sessionId)

        Task.detached {
            var metrics = await computeMetrics(
                transcriptPath: transcriptPath,
                model: model,
                skipLastMessage: payloadLastMessage != nil
            )
            if let payloadLastMessage {
                metrics.lastMessage = payloadLastMessage
            }

            await MainActor.run {
                var isStillWaitingForInput = false
                if let s = manager.session(for: sessionId) {
                    s.totalInputTokens = metrics.inputTokens
                    s.totalOutputTokens = metrics.outputTokens
                    s.totalCachedTokens = metrics.cachedTokens
                    s.estimatedCost = metrics.estimatedCost
                    if !metrics.lastMessage.isEmpty {
                        s.lastAssistantMessage = metrics.lastMessage
                    }
                    isStillWaitingForInput =
                        s.status == .done && s.doneAt == finalizedAt
                }
                if !muted, isStillWaitingForInput {
                    // Logged so an off-by-one message mix-up can be traced.
                    Log.notification.debug(
                        "Completion message: \(metrics.lastMessage.prefix(60))"
                    )
                    NotificationCenter.default.post(
                        name: .agentNotchSessionCompleted,
                        object: sessionId,
                        userInfo: [
                            "projectName": projectName,
                            "sessionTitle": sessionTitle as Any,
                            "gitBranch": gitBranch as Any,
                            "isWorktree": isWorktree,
                            "message": metrics.lastMessage,
                            "pid": pid as Any,
                            "tty": tty as Any,
                        ]
                    )
                    SoundPlayer.play(.sessionCompleted)
                }
                manager.notifyChange()
            }
        }
    }

    // MARK: - Off-MainActor computation

    private struct Metrics {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cachedTokens: Int = 0
        var estimatedCost: Double = 0.0
        var lastMessage: String = ""
    }

    /// Parses the transcript to compute tokens, cost, and the last message. Safe to call
    /// off the MainActor.
    ///
    /// **Waits for writes to settle before reading.** The `Stop` hook fires as soon as the
    /// agent finishes responding, and the append to the transcript may not be done yet.
    /// Reading without waiting misses the last entry, and the completion notification
    /// shows the previous message.
    private nonisolated static func computeMetrics(
        transcriptPath: String?,
        model: String?,
        skipLastMessage: Bool = false
    ) async -> Metrics {
        var metrics = Metrics()

        if let path = transcriptPath {
            await TranscriptParser.waitUntilSettled(at: path)
        }

        if let path = transcriptPath, let model {
            let usage = TranscriptParser.parseCumulativeUsage(at: path)
            metrics.inputTokens = usage.inputTokens
            metrics.outputTokens = usage.outputTokens
            metrics.cachedTokens = usage.cachedTokens
            metrics.estimatedCost = CostCalculator.estimateCost(
                model: model,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                cachedTokens: usage.cachedTokens
            )
        }
        if let path = transcriptPath, !skipLastMessage {
            metrics.lastMessage = TranscriptParser.lastAssistantMessage(at: path) ?? ""
        }

        return metrics
    }

}
