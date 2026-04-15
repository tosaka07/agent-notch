import AgentNotchCore
import Foundation

/// Unix socket サーバーを立ち上げ、受信メッセージを EventProcessor 経由で SessionManager に反映する。
/// また、View から呼ばれる permission 応答（approve/deny/answer）の窓口を提供する。
@MainActor
final class SocketCoordinator {
    private let sessionManager: SessionManager
    private var socketServer: SocketServer?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func start() {
        let manager = sessionManager
        do {
            let server = try SocketServer { message, _ in
                // Parse off MainActor — pure data processing
                let parsed = EventProcessor.parseMessage(message)
                // Capture needed fields before crossing isolation boundary
                let cwd = message["cwd"] as? String
                let transcriptPath = message["transcript_path"] as? String
                let pid = (message["_pid"] as? NSNumber)?.int32Value
                let tty = message["_tty"] as? String

                Task { @MainActor in
                    EventProcessor.apply(parsed.event, agentType: parsed.agentType, manager: manager)
                    EventProcessor.backfillSession(
                        parsed.sessionId, cwd: cwd, transcriptPath: transcriptPath,
                        pid: pid, tty: tty, manager: manager
                    )
                }

                // Never block the agent — respond immediately
                return [String: Any]()
            }
            server.start()
            socketServer = server
        } catch {
            Log.socket.error("Failed to start socket server: \(error)")
        }
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
            answerQuestion: { [weak self] sessionId, toolUseId, answer in
                self?.answer(sessionId: sessionId, toolUseId: toolUseId, answer: answer)
            }
        )
    }

    private func approve(sessionId: String, toolUseId: String) {
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "allow", reason: nil)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }

    private func deny(sessionId: String, toolUseId: String, reason: String?) {
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "deny", reason: reason)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }

    private func answer(sessionId: String, toolUseId: String, answer: String) {
        // AskUserQuestion response format
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "allow", reason: answer)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingQuestion = nil
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }
}
