import AgentNotchCore
import Foundation

/// Unix socket サーバーを立ち上げ、受信メッセージを EventProcessor 経由で SessionManager に反映する。
/// また、View から呼ばれる permission 応答（approve/deny/answer）の窓口を提供する。
@MainActor
final class SocketCoordinator {
    private let sessionManager: SessionManager
    private var socketServer: SocketServer?
    /// onMessage クロージャから SocketServer 自身を参照するための holder。
    /// SocketCoordinator が所有することで start() を抜けても解放されない。
    /// server は weak で持つので循環しない（強参照は socketServer property が担う）。
    private let serverBox = ServerBox()

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func start() {
        let manager = sessionManager
        let serverBox = self.serverBox

        do {
            let server = try SocketServer(onMessage: { [serverBox] message, connection in
                // Parse off MainActor — pure data processing
                let parsed = EventProcessor.parseMessage(message)
                let hookEvent = message["hook_event_name"] as? String ?? ""
                // 受信した全 hook を可視化（unknown も含め、何が飛んでくるか追えるように）
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

                // `PermissionRequest` hook 経由のときだけ deferred にする（tool_response を注入できる唯一の経路）。
                // `PreToolUse` 経由の AskUserQuestion は即時応答しないと agent がブロックされる上、
                // 応答しても tool_response にならないので pass-through。
                let deferred: (kind: PendingSocketResponse.Kind, sessionId: String, toolUseId: String, toolInput: JSONBox?)?
                switch parsed.event {
                case let .askQuestion(info) where hookEvent == "PermissionRequest":
                    // 応答時に questions を含む元の tool_input を復元するために保持する（#6）。
                    let rawToolInput = message["tool_input"] as? [String: Any]
                    deferred = (.askUserQuestion, info.sessionId, info.toolUseId, rawToolInput.map(JSONBox.init))
                case let .permissionRequested(info):
                    deferred = (.permissionRequest, info.sessionId, info.toolUseId, nil)
                default:
                    deferred = nil
                }

                // deferred なケースは、addPending の成否を「先に」同期的に確定させる
                // （addPending 自体は MainActor 非依存で同期）。
                // ここで成功しなかった（＝既存 toolUseId と衝突＝ハイジャック試行）場合、
                // 後段の apply で UI に pendingPermissions/pendingQuestion を追加してしまうと、
                // ユーザー視点では正規の承認リクエストに見えるのに、実際に承認/拒否した応答は
                // 攻撃者が握る新規 connection に送られてしまう（security review 指摘）。
                // そのため apply 自体をスキップし、新規 connection を閉じて即 return する。
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
                    // 同一プロセス（pid）が resume/compact/clear で新しい session_id を発行した場合、
                    // 古いセッションを新しい方へ統合する（#23: 一覧の分裂対策）。source が
                    // startup（teammate の新規セッション起動等も含む）の場合は統合しない。
                    // pid だけでなく cwd も一致条件に含めることで、_pid を偽装した SessionStart
                    // 送信による他セッションの乗っ取りの難易度を上げている（レビュー指摘 / issue #24 で恒久対策）。
                    // SessionStart は deferred ではないため pendingRegistered は常に true だが、
                    // reconcile 自体は apply より前・pendingRegistered ガードの外で行ってよい。
                    if hookEvent == "SessionStart" {
                        manager.reconcileSessionStart(
                            newId: parsed.sessionId, pid: pid, cwd: cwd, source: sessionStartSource
                        )
                    }
                    if pendingRegistered {
                        EventProcessor.apply(parsed.event, agentType: parsed.agentType, manager: manager)
                    }
                    EventProcessor.backfillSession(
                        parsed.sessionId, cwd: cwd, transcriptPath: transcriptPath,
                        pid: pid, tty: tty, manager: manager
                    )
                    EventProcessor.applyPermissionMode(
                        sessionId: parsed.sessionId, rawMode: permissionMode, manager: manager
                    )
                }

                // deferred でなければ即時の空応答（pass-through）を返す。
                // deferred の場合は成功・拒否いずれも応答は別経路（deferred送信 or 即クローズ）
                // 済みなので、ここでは常に nil（immediate な応答をしない）を返す。
                guard deferred != nil else { return [String: Any]() }
                return nil
            }, onPendingExpired: { pending in
                // socket queue 上で呼ばれる。hook が recv timeout で去った/TTL 破棄された
                // pending をセッション状態に反映し、バナーを失効表示に切り替える（issue #28）。
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

    /// onMessage クロージャから SocketServer 自身を参照するための holder。
    /// `server` は weak 参照。強参照は SocketCoordinator.socketServer が持つので循環しない。
    private final class ServerBox: @unchecked Sendable {
        weak var server: SocketServer?
    }

    func stop() {
        socketServer?.stop()
        socketServer = nil
    }

    // MARK: - Permission actions (exposed to SwiftUI via EnvironmentValues)

    /// `.environment(\.permissionActions, socket.permissionActions)` で View に注入する。
    var permissionActions: PermissionActions {
        PermissionActions(
            approve: { [weak self] sessionId, toolUseId in
                self?.approve(sessionId: sessionId, toolUseId: toolUseId)
            },
            deny: { [weak self] sessionId, toolUseId, reason in
                self?.deny(sessionId: sessionId, toolUseId: toolUseId, reason: reason)
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
        let delivered = socketServer?.respondToPermission(
            toolUseId: toolUseId, decision: "allow", reason: nil
        ) ?? false
        if delivered {
            clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
        } else {
            markPermissionExpired(sessionId: sessionId, toolUseId: toolUseId)
        }
    }

    private func deny(sessionId: String, toolUseId: String, reason: String?) {
        let delivered = socketServer?.respondToPermission(
            toolUseId: toolUseId, decision: "deny", reason: reason
        ) ?? false
        if delivered {
            clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
        } else {
            markPermissionExpired(sessionId: sessionId, toolUseId: toolUseId)
        }
    }

    /// AskUserQuestion の回答を Claude Code の仕様に合わせて送る。
    /// `decision.updatedInput.answers` に `{question: answer}` 形式で注入される。
    /// multi-select の場合は value を " / " で結合する（Claude Code は単一文字列を期待）。
    /// 応答経路が失効していた場合はバナーを消さず失効表示に切り替える（issue #28:
    /// 送れていないのに送れたように見せない）。
    private func answer(sessionId: String, toolUseId: String, answers: [String: [String]]) {
        guard let session = sessionManager.session(for: sessionId),
              session.pendingQuestion?.toolUseId == toolUseId else {
            // stale な View からの二重送信等。対応する pendingQuestion が無いなら何もしない。
            Log.socket.warning("answer: no matching pendingQuestion session=\(sessionId) toolUseId=\(toolUseId)")
            return
        }
        let flatAnswers = answers.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = pair.value.joined(separator: " / ")
        }
        let delivered = socketServer?.respondToAskQuestion(
            toolUseId: toolUseId, answers: flatAnswers
        ) ?? false
        if delivered {
            session.pendingQuestion = nil
            // #19: 他にまだ pending な承認/質問があれば permissionWaiting を維持し、
            // 無ければ subagent 実行中かどうかで復帰先を決める（thinking に決め打ちしない）。
            session.status = session.statusAfterPermissionResolved()
        } else if var question = session.pendingQuestion {
            question.isExpired = true
            session.pendingQuestion = question
        }
        sessionManager.notifyChange()
    }

    /// 応答が届けられなかった permission を失効表示（canRespond=false）に切り替える。
    private func markPermissionExpired(sessionId: String, toolUseId: String) {
        EventProcessor.applyPendingExpired(
            sessionId: sessionId, toolUseId: toolUseId, kind: .permissionRequest, manager: sessionManager
        )
    }

    /// 失効した質問/権限バナーをユーザー操作で閉じる。
    private func dismissExpired(sessionId: String, toolUseId: String) {
        guard let session = sessionManager.session(for: sessionId) else { return }
        if session.pendingQuestion?.toolUseId == toolUseId {
            session.pendingQuestion = nil
        }
        session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
        session.status = session.statusAfterPermissionResolved()
        sessionManager.notifyChange()
    }

    private func clearPendingPermission(sessionId: String, toolUseId: String) {
        guard let session = sessionManager.session(for: sessionId) else { return }
        session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
        // #19: 他にまだ pending な承認/質問があれば permissionWaiting を維持し、
        // 無ければ subagent 実行中かどうかで復帰先を決める（thinking に決め打ちしない）。
        session.status = session.statusAfterPermissionResolved()
        sessionManager.notifyChange()
    }
}
