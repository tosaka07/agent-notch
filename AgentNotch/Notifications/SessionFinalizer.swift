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
    ///   タスク完了音と聞き分けられるようにする。ただし teammate セッション
    ///   （`teammateName != nil`）は Stop 経由で来ても常に `.subagentCompleted` を鳴らす
    ///   （Stop / TeammateIdle のどちらが先に来ても音が一貫するように）。
    static func finalize(sessionId: String, manager: SessionManager, completionSound: SoundEvent = .sessionCompleted) {
        guard let session = manager.session(for: sessionId) else { return }

        // 再入ガード: teammate は「Stop（sessionCompleted）→ 結果メッセージ送信 →
        // TeammateIdle（subagentCompleted）」の順でイベントが飛ぶことがあり、
        // TeammateIdle は idle のたびに繰り返し飛ぶこともある。すでに done なら
        // 完了通知・サウンドを二重発火させず、doneAt も更新しない
        // （完了アニメーションの基準がリセットされるのを防ぐ）。
        // 次ターンの UserPromptSubmit で status が .thinking に戻るため、
        // 正当な次回の finalize はここを通る。
        guard session.status != .done else {
            Log.events.debug("finalize skipped (already done) id=\(sessionId)")
            return
        }

        Log.events.info("sessionIdle (done) id=\(sessionId)")
        let sound: SoundEvent = session.teammateName != nil ? .subagentCompleted : completionSound

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
            let metrics = await computeMetrics(transcriptPath: transcriptPath, model: model)

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
                    // 「1 つ前のメッセージが出る」類の取り違えを追えるようにしておく。
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
                    SoundPlayer.play(sound)
                }
                manager.notifyChange()
            }
        }
    }

    // MARK: - Off-MainActor computation

    /// transcript の追記完了を待つ回数と間隔。
    private nonisolated static let settleAttempts = 6
    private nonisolated static let settleInterval: Duration = .milliseconds(80)

    private struct Metrics {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cachedTokens: Int = 0
        var estimatedCost: Double = 0.0
        var lastMessage: String = ""
    }

    /// transcript をパースして token/cost/最終メッセージを計算する。MainActor 外でも安全に呼べる。
    ///
    /// 読む前に**書き込みが落ち着くのを待つ**。`Stop` hook は agent が応答を終えた時点で
    /// 飛んでくるが、そのとき transcript への追記はまだ済んでいないことがある。待たずに
    /// 読むと最後の 1 件が入っておらず、**1 つ前のメッセージが完了通知に出る**。
    private nonisolated static func computeMetrics(
        transcriptPath: String?,
        model: String?
    ) async -> Metrics {
        var metrics = Metrics()

        if let path = transcriptPath {
            await waitForTranscriptToSettle(at: path)
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
        if let path = transcriptPath {
            metrics.lastMessage = TranscriptParser.lastAssistantMessage(at: path) ?? ""
        }

        return metrics
    }

    /// transcript のサイズが変わらなくなるまで待つ（上限 `settleAttempts × settleInterval`）。
    ///
    /// 「追記が終わった」ことを知る手段が無いので、サイズが 2 回続けて同じなら
    /// 書き終わったとみなす。通知が出るまでの遅れは最大でも 0.5 秒程度に収める
    /// （完了に気づくのが遅れる方が、内容が古いより困る場面もあるため）。
    private nonisolated static func waitForTranscriptToSettle(at path: String) async {
        var previousSize: Int?
        for _ in 0..<settleAttempts {
            let size = fileSize(at: path)
            if let previousSize, size == previousSize { return }
            previousSize = size
            try? await Task.sleep(for: settleInterval)
        }
    }

    private nonisolated static func fileSize(at path: String) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return 0
        }
        return attributes[.size] as? Int ?? 0
    }
}
