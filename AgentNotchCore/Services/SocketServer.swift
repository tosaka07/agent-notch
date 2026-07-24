import Foundation
import Network

public struct PendingSocketResponse: Sendable {
    /// どの hook イベントに応答するか。respondToPermission が stdout (hookSpecificOutput)
    /// を組み立てるときのイベント名として使う。
    public enum Kind: String, Sendable {
        /// PreToolUse hook の AskUserQuestion ツール呼び出しに対する応答
        case askUserQuestion
        /// PermissionRequest hook への応答
        case permissionRequest
    }

    public let kind: Kind
    public let sessionId: String
    public let toolUseId: String
    public let connection: NWConnection
    public let receivedAt: Date
    /// `askUserQuestion` の場合のみ、元の `tool_input`（`questions` を含む）を保持する。
    /// Claude Code は `updatedInput` をツールの入力スキーマ全体として検証するため、
    /// `answers` だけを返すと必須の `questions` が欠落してバリデーションエラーになる。
    /// 応答時に元の `tool_input` に `answers` をマージして送り返す必要がある。
    public let toolInput: JSONBox?

    public init(
        kind: Kind, sessionId: String, toolUseId: String, connection: NWConnection, receivedAt: Date,
        toolInput: JSONBox? = nil
    ) {
        self.kind = kind
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.connection = connection
        self.receivedAt = receivedAt
        self.toolInput = toolInput
    }
}

/// `[String: Any]` を Sendable な境界を跨いで受け渡すための箱。
/// hook JSON はプリミティブ値のみで構成され、SocketServer 内部でしか使わないため
/// `@unchecked Sendable` として扱う（LockedArray / LockedDict と同様の許容）。
public final class JSONBox: @unchecked Sendable {
    public let value: [String: Any]
    public init(_ value: [String: Any]) { self.value = value }
}

public final class SocketServer: Sendable {
    public static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.agentnotch.socketserver", qos: .userInitiated)
    public let onMessage: @Sendable ([String: Any], NWConnection) -> [String: Any]?

    private let _connections = LockedArray<SocketConnection>()
    private let _pending = LockedDict<String, PendingSocketResponse>()

    public init(onMessage: @escaping @Sendable ([String: Any], NWConnection) -> [String: Any]?) throws {
        self.onMessage = onMessage

        Self.removeStaleSocket()

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        self.listener = try NWListener(using: params)
    }

    public func start() {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case let .failed(error):
                Log.socket.error("listener failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] nwConnection in
            guard let self else { return }
            let conn = SocketConnection(
                connection: nwConnection,
                queue: self.queue,
                onMessage: self.onMessage
            )
            self._connections.append(conn)
            conn.start()
        }

        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
        for conn in _connections.removeAll() { conn.cancel() }
        for (_, p) in _pending.all() { p.connection.cancel() }
        _pending.removeAll()
        Self.removeStaleSocket()
    }

    // MARK: - Deferred Permission Response

    public func addPending(_ response: PendingSocketResponse) {
        _pending.set(response.toolUseId, response)
    }

    /// 通常の PermissionRequest（tool allow/deny）の応答を送る。
    public func respondToPermission(toolUseId: String, decision: String, reason: String?) {
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": decision, "message": reason ?? ""]
            ]
        ]
        sendDeferredResponse(toolUseId: toolUseId, response: response, logContext: "permission decision=\(decision)")
    }

    /// AskUserQuestion の回答を送る。
    /// Claude Code 内部の期待形式: `hookSpecificOutput.decision.updatedInput.answers` に
    /// `{question_text: answer_label}` の dict を入れる。
    /// `updatedInput` は AskUserQuestion ツールの入力スキーマ全体として検証されるため、
    /// 元の `tool_input`（`questions` を含む）を土台にして `answers` を足し込む。
    /// これを怠ると「required parameter questions is missing」で失敗する（#6）。
    public func respondToAskQuestion(toolUseId: String, answers: [String: String]) {
        var updatedInput = _pending.peek(toolUseId)?.toolInput?.value ?? [:]
        updatedInput["answers"] = answers
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "updatedInput": updatedInput
                ]
            ]
        ]
        sendDeferredResponse(toolUseId: toolUseId, response: response, logContext: "askUserQuestion answers=\(answers.count)")
    }

    private func sendDeferredResponse(toolUseId: String, response: [String: Any], logContext: String) {
        guard let pending = _pending.remove(toolUseId) else {
            Log.socket.error("sendDeferredResponse: no pending for toolUseId=\(toolUseId) (\(logContext))")
            return
        }
        Log.socket.info("sendDeferredResponse kind=\(pending.kind.rawValue) toolUseId=\(toolUseId) \(logContext)")
        guard let data = try? SocketProtocol.encode(response) else {
            Log.socket.error("sendDeferredResponse: encode failed")
            pending.connection.cancel()
            return
        }
        pending.connection.send(content: data, completion: .contentProcessed { _ in
            pending.connection.cancel()
        })
    }

    public func cancelPending(sessionId: String) {
        for (key, val) in _pending.all() {
            if val.sessionId == sessionId {
                val.connection.cancel()
                _pending.remove(key)
            }
        }
    }

    private static func removeStaleSocket() {
        let fm = FileManager.default
        if fm.fileExists(atPath: socketPath) {
            try? fm.removeItem(atPath: socketPath)
        }
    }
}

// MARK: - Thread-safe collections

final class LockedArray<Element: Sendable>: @unchecked Sendable {
        private var elements: [Element] = []
        private let lock = NSLock()

        func append(_ element: Element) {
            lock.lock()
            elements.append(element)
            lock.unlock()
        }

        func removeAll() -> [Element] {
            lock.lock()
            let copy = elements
            elements.removeAll()
            lock.unlock()
            return copy
        }
}

final class LockedDict<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private var dict: [Key: Value] = [:]
    private let lock = NSLock()

    func set(_ key: Key, _ value: Value) {
        lock.lock(); dict[key] = value; lock.unlock()
    }

    @discardableResult
    func remove(_ key: Key) -> Value? {
        lock.lock(); let v = dict.removeValue(forKey: key); lock.unlock(); return v
    }

    /// 削除せずに参照するだけの取得。
    func peek(_ key: Key) -> Value? {
        lock.lock(); let v = dict[key]; lock.unlock(); return v
    }

    func all() -> [(Key, Value)] {
        lock.lock(); let items = Array(dict); lock.unlock(); return items
    }

    func removeAll() {
        lock.lock(); dict.removeAll(); lock.unlock()
    }
}
