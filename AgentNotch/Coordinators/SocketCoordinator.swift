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
            let server = try SocketServer { [serverBox] message, connection in
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
            }
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
            }
        )
    }

    private func approve(sessionId: String, toolUseId: String) {
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "allow", reason: nil)
        clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
    }

    private func deny(sessionId: String, toolUseId: String, reason: String?) {
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "deny", reason: reason)
        clearPendingPermission(sessionId: sessionId, toolUseId: toolUseId)
    }

    /// AskUserQuestion の回答を Claude Code の仕様に合わせて送る。
    /// `decision.updatedInput.answers` に `{question: answer}` 形式で注入される。
    /// multi-select の場合は value を " / " で結合する（Claude Code は単一文字列を期待）。
    private func answer(sessionId: String, toolUseId: String, answers: [String: [String]]) {
        let flatAnswers = answers.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = pair.value.joined(separator: " / ")
        }
        socketServer?.respondToAskQuestion(toolUseId: toolUseId, answers: flatAnswers)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingQuestion = nil
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }

    private func clearPendingPermission(sessionId: String, toolUseId: String) {
        guard let session = sessionManager.session(for: sessionId) else { return }
        session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
        session.status = .thinking
        sessionManager.notifyChange()
    }
}
