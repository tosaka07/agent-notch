import AgentNotchCore
import Foundation

/// `.sessionIdle`（セッション完了）イベントの重量級処理を担当する。
///
/// セッション状態を done に変えた上で、transcript を background でパースして
/// token/cost を確定し、完了通知（`.agentNotchSessionCompleted`）を発火する。
///
/// I/O が重いため必ず `Task.detached` で走らせる。
@MainActor
enum SessionFinalizer {
    /// セッションを完了扱いにし、非同期で transcript を読み込んで UI に反映する。
    /// - Parameter completionSound: 完了時に鳴らすサウンド。通常の Stop は `.sessionCompleted`、
    ///   agent teams の teammate 完了（TeammateIdle）は `.subagentCompleted` を渡し、
    ///   タスク完了音と聞き分けられるようにする。
    static func finalize(sessionId: String, manager: SessionManager, completionSound: SoundEvent = .sessionCompleted) {
        Log.events.info("sessionIdle (done) id=\(sessionId)")
        guard let session = manager.session(for: sessionId) else { return }

        session.status = .done
        session.doneAt = Date()
        session.currentTool = nil
        session.pendingPermissions.removeAll()
        session.pendingQuestion = nil
        session.foldRunningSubagentsToCompleted()

        // 非同期処理のために MainActor で値を snapshot
        let transcriptPath = session.transcriptPath
        let model = session.model
        let projectName = session.originRepoName
            ?? (session.cwd as NSString?)?.lastPathComponent ?? "Session"
        let sessionTitle = session.sessionTitle
        let gitBranch = session.gitBranch
        let isWorktree = session.worktreeName != nil
        let pid = session.pid
        let tty = session.tty
        let muted = manager.isMuted(sessionId)

        Task.detached {
            let metrics = computeMetrics(transcriptPath: transcriptPath, model: model)

            await MainActor.run {
                if let s = manager.session(for: sessionId) {
                    s.totalInputTokens = metrics.inputTokens
                    s.totalOutputTokens = metrics.outputTokens
                    s.totalCachedTokens = metrics.cachedTokens
                    s.estimatedCost = metrics.estimatedCost
                    if !metrics.lastMessage.isEmpty {
                        s.lastAssistantMessage = metrics.lastMessage
                    }
                }
                if !muted {
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
                    SoundPlayer.play(completionSound)
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

    /// transcript をパースして token/cost/最終メッセージを計算する。MainActor 外でも安全に呼べる。
    private nonisolated static func computeMetrics(transcriptPath: String?, model: String?) -> Metrics {
        var metrics = Metrics()

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
        if let path = transcriptPath {
            metrics.lastMessage = TranscriptParser.lastAssistantMessage(at: path) ?? ""
        }

        return metrics
    }
}
