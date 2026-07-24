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
        startSweepTimer()
    }

    public func stop() {
        listener.cancel()
        _sweepTimer.get()?.cancel()
        _sweepTimer.set(nil)
        for conn in _connections.removeAll() { conn.cancel() }
        for (_, p) in _pending.all() { p.connection.cancel() }
        _pending.removeAll()
        Self.removeStaleSocket()
    }

    // MARK: - Deferred Permission Response

    /// TTL（`_pending` エントリの生存期間上限）。
    /// `HookHandler.recvTimeoutSeconds`（120s）が実際の待ち上限で、hook プロセスは
    /// その時間で recv を諦めて pass-through に倒れる（`HookInstaller` の
    /// PermissionRequest hook timeout ＝ 86400s は Claude Code 側の外側タイムアウトで、
    /// 内側の 120s の方が必ず先に発火するため拘束力を持たない）。
    /// よって 120s を超えたエントリは応答が届いても意味がなく、破棄してよい。
    /// 多少のマージンとして 10s 足す。
    static let pendingTTLSeconds: TimeInterval = 130
    private static let sweepIntervalSeconds: TimeInterval = 30

    private let _sweepTimer = LockedBox<DispatchSourceTimer>()

    /// `_pending` へ登録する。同じ `toolUseId` が既に登録されている場合は「先勝ち」とし、
    /// 既存エントリを保持したまま登録を拒否する（socket ハイジャック対策 #24）。
    /// 呼び出し側は戻り値が `false` の場合、新規 connection を閉じること。
    @discardableResult
    public func addPending(_ response: PendingSocketResponse) -> Bool {
        let inserted = _pending.setIfAbsent(response.toolUseId, response)
        if !inserted {
            Log.socket.warning(
                "addPending: toolUseId=\(response.toolUseId) は既に登録済み。衝突を検知したため新規登録を拒否（先勝ち）。sessionId=\(response.sessionId) kind=\(response.kind.rawValue)"
            )
        }
        return inserted
    }

    /// TTL を超過した pending エントリを破棄し、connection をクローズする（#25）。
    /// sweep タイマーから定期的に呼ばれる。純粋なロジック部分は `isExpired` に切り出してテスト可能にしている。
    func sweepExpiredPending(now: Date = Date()) {
        let expired = _pending.removeAll { Self.isExpired(receivedAt: $0.receivedAt, now: now) }
        for pending in expired {
            Log.socket.warning(
                "sweepExpiredPending: TTL 超過（\(Self.pendingTTLSeconds)s）で破棄 toolUseId=\(pending.toolUseId) sessionId=\(pending.sessionId) kind=\(pending.kind.rawValue)"
            )
            pending.connection.cancel()
        }
    }

    /// `receivedAt` から `now` までの経過時間が TTL 以上かどうかを判定する純関数。
    static func isExpired(receivedAt: Date, now: Date, ttl: TimeInterval = pendingTTLSeconds) -> Bool {
        now.timeIntervalSince(receivedAt) >= ttl
    }

    private func startSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.sweepIntervalSeconds, repeating: Self.sweepIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.sweepExpiredPending()
        }
        timer.resume()
        _sweepTimer.set(timer)
    }

    /// 通常の PermissionRequest（tool allow/deny）の応答を送る。
    public func respondToPermission(toolUseId: String, decision: String, reason: String?) {
        // `_pending` から一度だけ remove し、その結果を土台に応答を組み立てて同じエントリの
        // connection に送る。peek→remove の二段構成は TOCTOU（間に cancelPending 等が割り込むと
        // 応答先 connection と内容が食い違う、または無応答になる）になるため一発ロック化している。
        guard let pending = _pending.remove(toolUseId) else {
            Log.socket.error("respondToPermission: no pending for toolUseId=\(toolUseId) decision=\(decision)")
            return
        }
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": decision, "message": reason ?? ""]
            ]
        ]
        sendDeferredResponse(pending, response: response, logContext: "permission decision=\(decision)")
    }

    /// AskUserQuestion の回答を送る。
    /// Claude Code 内部の期待形式: `hookSpecificOutput.decision.updatedInput.answers` に
    /// `{question_text: answer_label}` の dict を入れる。
    /// `updatedInput` は AskUserQuestion ツールの入力スキーマ全体として検証されるため、
    /// 元の `tool_input`（`questions` を含む）を土台にして `answers` を足し込む。
    /// これを怠ると「required parameter questions is missing」で失敗する（#6）。
    public func respondToAskQuestion(toolUseId: String, answers: [String: String]) {
        guard let pending = _pending.remove(toolUseId) else {
            Log.socket.error("respondToAskQuestion: no pending for toolUseId=\(toolUseId)")
            return
        }
        var updatedInput = pending.toolInput?.value ?? [:]
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
        sendDeferredResponse(pending, response: response, logContext: "askUserQuestion answers=\(answers.count)")
    }

    /// すでに `_pending` から取り出し済みの `PendingSocketResponse` を使って応答を送る。
    /// 削除は呼び出し側の責務（remove 1 回きりの一発ロック化のため）。
    private func sendDeferredResponse(_ pending: PendingSocketResponse, response: [String: Any], logContext: String) {
        Log.socket.info("sendDeferredResponse kind=\(pending.kind.rawValue) toolUseId=\(pending.toolUseId) \(logContext)")
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

    /// キーが未登録の場合のみ値を挿入する（check-and-set をロック内で一発化し TOCTOU を避ける）。
    /// 戻り値: 挿入できたら true、既に存在して拒否したら false。
    @discardableResult
    func setIfAbsent(_ key: Key, _ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if dict[key] != nil { return false }
        dict[key] = value
        return true
    }

    @discardableResult
    func remove(_ key: Key) -> Value? {
        lock.lock(); let v = dict.removeValue(forKey: key); lock.unlock(); return v
    }

    func all() -> [(Key, Value)] {
        lock.lock(); let items = Array(dict); lock.unlock(); return items
    }

    /// `predicate` を満たすエントリを削除し、削除した値の一覧を返す。
    @discardableResult
    func removeAll(where predicate: (Value) -> Bool) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        var removed: [Value] = []
        for (key, value) in dict where predicate(value) {
            removed.append(value)
            dict.removeValue(forKey: key)
        }
        return removed
    }

    func removeAll() {
        lock.lock(); dict.removeAll(); lock.unlock()
    }
}

/// 単一の値を lock 付きで保持するホルダー（mutable な var を持てない `Sendable` class から
/// タイマー等の参照型状態を安全に持ち回すために使う）。
final class LockedBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()

    func set(_ newValue: T?) {
        lock.lock(); value = newValue; lock.unlock()
    }

    func get() -> T? {
        lock.lock(); defer { lock.unlock() }; return value
    }
}
