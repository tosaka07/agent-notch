import Foundation
import Network

public struct PendingSocketResponse: Sendable {
    /// Which hook event is being answered. Used as the event name when respondToPermission
    /// builds the stdout `hookSpecificOutput`.
    public enum Kind: String, Sendable {
        /// Response to an AskUserQuestion tool call on the PreToolUse hook.
        case askUserQuestion
        /// Response to the PermissionRequest hook.
        case permissionRequest
    }

    public let kind: Kind
    public let sessionId: String
    public let toolUseId: String
    public let connection: NWConnection
    public let receivedAt: Date
    /// Only for `askUserQuestion`: the original `tool_input`, including `questions`.
    /// Claude Code validates `updatedInput` against the tool's entire input schema, so replying
    /// with just `answers` drops the required `questions` and fails validation. The response must
    /// merge `answers` into the original `tool_input`.
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

/// Box for passing a `[String: Any]` across a Sendable boundary.
/// Hook JSON contains only primitive values and never leaves SocketServer, so it is treated as
/// `@unchecked Sendable`, the same allowance made for LockedArray and LockedDict.
public final class JSONBox: @unchecked Sendable {
    public let value: [String: Any]
    public init(_ value: [String: Any]) { self.value = value }
}

public final class SocketServer: Sendable {
    public static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"

    private let boundSocketPath: String
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.agentnotch.socketserver", qos: .userInitiated)
    public let onMessage: @Sendable ([String: Any], NWConnection) -> [String: Any]?
    /// Called when a pending entry can no longer be answered: the hook process gave up on its recv
    /// timeout, died, or the TTL elapsed. The UI switches the corresponding banner to an expired
    /// state, so that a response which cannot arrive does not silently look like it was sent.
    /// Note that this runs on the socket queue.
    public let onPendingExpired: (@Sendable (PendingSocketResponse) -> Void)?

    private let _connections = LockedArray<SocketConnection>()
    private let _pending = LockedDict<String, PendingSocketResponse>()

    public init(
        socketPath: String = SocketServer.socketPath,
        onMessage: @escaping @Sendable ([String: Any], NWConnection) -> [String: Any]?,
        onPendingExpired: (@Sendable (PendingSocketResponse) -> Void)? = nil
    ) throws {
        self.boundSocketPath = socketPath
        self.onMessage = onMessage
        self.onPendingExpired = onPendingExpired

        Self.removeStaleSocket(at: socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        self.listener = try NWListener(using: params)
    }

    public func start() {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
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
        // Remove before cancelling, for the same reason as cancelPending: this is a deliberate
        // teardown, so onPendingExpired must not fire via watchPendingConnection.
        let pendings = _pending.all()
        _pending.removeAll()
        for (_, p) in pendings { p.connection.cancel() }
        Self.removeStaleSocket(at: boundSocketPath)
    }

    // MARK: - Deferred Permission Response

    /// Lifetime cap on a `_pending` entry.
    /// The real limit is `HookHandler.recvTimeoutSeconds` (120s), after which the hook process
    /// gives up on recv and falls through. (`HookInstaller`'s 86400s PermissionRequest hook timeout
    /// is Claude Code's outer timeout and never binds, because the inner 120s always fires first.)
    /// Past 120s a response would be meaningless, so the entry can be discarded; 10s is added as
    /// margin. Normally the EOF detection in `watchPendingConnection` notices expiry first, so this
    /// TTL sweep is a backstop for the abnormal case where no EOF arrives.
    static let pendingTTLSeconds: TimeInterval = TimeInterval(HookHandler.recvTimeoutSeconds) + 10
    private static let sweepIntervalSeconds: TimeInterval = 30

    private let _sweepTimer = LockedBox<DispatchSourceTimer>()

    /// Registers an entry in `_pending`. If the same `toolUseId` is already registered, first
    /// writer wins: the existing entry is kept and the new one rejected, which guards against
    /// socket hijacking. Callers must close the new connection when this returns `false`.
    @discardableResult
    public func addPending(_ response: PendingSocketResponse) -> Bool {
        let inserted = _pending.setIfAbsent(response.toolUseId, response)
        if !inserted {
            Log.socket.warning(
                "addPending: toolUseId=\(response.toolUseId) already registered; rejecting the new registration (first writer wins). sessionId=\(response.sessionId) kind=\(response.kind.rawValue)"
            )
        } else {
            watchPendingConnection(response)
        }
        return inserted
    }

    /// Watches a deferred connection for disconnection (EOF or error).
    /// After sending, the hook process only blocks on recv and never sends more data, so this
    /// receive completing means either the hook closed the connection (recv timeout elapsed or the
    /// process exited) or we cancelled it after sending a response. In the first case the pending
    /// entry is discarded and `onPendingExpired` notifies the UI; in the second the entry was
    /// already removed, so it is a no-op.
    private func watchPendingConnection(_ pending: PendingSocketResponse) {
        pending.connection.receive(minimumIncompleteLength: 1, maximumLength: 1) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }
            if content != nil, !isComplete, error == nil {
                // The protocol never sends data here, but if any arrives, discard it and keep watching.
                self.watchPendingConnection(pending)
                return
            }
            self.expirePending(toolUseId: pending.toolUseId, reason: "hook connection closed")
        }
    }

    /// Discards the pending entry, closes its connection, and calls `onPendingExpired`.
    /// Idempotent: does nothing if it was already answered or discarded (remove returns nil).
    private func expirePending(toolUseId: String, reason: String) {
        guard let removed = _pending.remove(toolUseId) else { return }
        Log.socket.warning(
            "expirePending: \(reason) toolUseId=\(toolUseId) sessionId=\(removed.sessionId) kind=\(removed.kind.rawValue)"
        )
        removed.connection.cancel()
        onPendingExpired?(removed)
    }

    /// Discards pending entries past their TTL and closes their connections.
    /// Called periodically by the sweep timer. The pure logic is factored into `isExpired` so it
    /// can be tested.
    func sweepExpiredPending(now: Date = Date()) {
        let expired = _pending.removeAll { Self.isExpired(receivedAt: $0.receivedAt, now: now) }
        for pending in expired {
            Log.socket.warning(
                "sweepExpiredPending: discarding past TTL (\(Self.pendingTTLSeconds)s) toolUseId=\(pending.toolUseId) sessionId=\(pending.sessionId) kind=\(pending.kind.rawValue)"
            )
            pending.connection.cancel()
            onPendingExpired?(pending)
        }
    }

    /// Pure predicate: whether the time from `receivedAt` to `now` has reached the TTL.
    static func isExpired(receivedAt: Date, now: Date, ttl: TimeInterval = pendingTTLSeconds) -> Bool {
        now.timeIntervalSince(receivedAt) >= ttl
    }

    private func startSweepTimer() {
        // If start() runs twice without an intervening stop(), creating a new timer while the old
        // one survives would sweep twice. Symmetrically with stop(), always cancel any existing
        // timer before creating one.
        _sweepTimer.get()?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.sweepIntervalSeconds, repeating: Self.sweepIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.sweepExpiredPending()
        }
        timer.resume()
        _sweepTimer.set(timer)
    }

    /// Sends the response to an ordinary PermissionRequest (tool allow/deny).
    /// Returns true if the response path is still alive and the send has begun; false when there is
    /// no pending entry (discarded by TTL, hook disconnected, or a duplicate response). On false the
    /// UI must tell the user that the response did not get through.
    @discardableResult
    public func respondToPermission(toolUseId: String, decision: String, reason: String?) -> Bool {
        // Remove from `_pending` exactly once, then build the response from that entry and send it
        // on that entry's connection. A peek-then-remove pair would be a TOCTOU: something like
        // cancelPending slipping in between could send the response on the wrong connection, or
        // send nothing at all. Hence the single locked operation.
        guard let pending = _pending.remove(toolUseId) else {
            Log.socket.error(
                "respondToPermission: no pending for toolUseId=\(toolUseId) decision=\(decision)")
            return false
        }
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": decision, "message": reason ?? ""],
            ]
        ]
        sendDeferredResponse(pending, response: response, logContext: "permission decision=\(decision)")
        return true
    }

    /// Releases a PermissionRequest back to the agent without allow/deny.
    ///
    /// The internal marker is consumed by `HookHandler` and never reaches the agent's stdout.
    /// With no hook decision, Codex immediately falls back to its native terminal approval
    /// prompt, including any option for updating future permissions.
    @discardableResult
    public func respondInTerminal(toolUseId: String) -> Bool {
        guard let pending = _pending.remove(toolUseId) else {
            Log.socket.error("respondInTerminal: no pending for toolUseId=\(toolUseId)")
            return false
        }
        sendDeferredResponse(
            pending,
            response: [HookResponseControl.respondInTerminalKey: true],
            logContext: "permission handed back to terminal"
        )
        return true
    }

    /// Sends the answers to an AskUserQuestion.
    /// Claude Code expects `hookSpecificOutput.decision.updatedInput.answers` to hold a
    /// `{question_text: answer_label}` dictionary.
    /// `updatedInput` is validated against the AskUserQuestion tool's entire input schema, so
    /// `answers` is added on top of the original `tool_input` (which carries `questions`).
    /// Skipping that fails with "required parameter questions is missing".
    /// The return value means the same as in `respondToPermission` (false = response path expired).
    @discardableResult
    public func respondToAskQuestion(toolUseId: String, answers: [String: String]) -> Bool {
        guard let pending = _pending.remove(toolUseId) else {
            Log.socket.error("respondToAskQuestion: no pending for toolUseId=\(toolUseId)")
            return false
        }
        var updatedInput = pending.toolInput?.value ?? [:]
        updatedInput["answers"] = answers
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "updatedInput": updatedInput,
                ],
            ]
        ]
        sendDeferredResponse(
            pending, response: response, logContext: "askUserQuestion answers=\(answers.count)")
        return true
    }

    /// Sends a response using a `PendingSocketResponse` already taken out of `_pending`.
    /// Removal is the caller's responsibility, so that remove happens exactly once under one lock.
    private func sendDeferredResponse(
        _ pending: PendingSocketResponse, response: [String: Any], logContext: String
    ) {
        Log.socket.info(
            "sendDeferredResponse kind=\(pending.kind.rawValue) toolUseId=\(pending.toolUseId) \(logContext)")
        guard let data = try? SocketProtocol.encode(response) else {
            Log.socket.error("sendDeferredResponse: encode failed")
            pending.connection.cancel()
            return
        }
        pending.connection.send(
            content: data,
            completion: .contentProcessed { _ in
                pending.connection.cancel()
            })
    }

    public func cancelPending(sessionId: String) {
        for (key, val) in _pending.all() {
            if val.sessionId == sessionId {
                // Remove before cancelling. Cancelling fires watchPendingConnection's handler, but
                // with the entry already removed expirePending is a no-op, so onPendingExpired is
                // not called for this deliberate teardown.
                _pending.remove(key)
                val.connection.cancel()
            }
        }
    }

    /// Cancels one deferred response path, used when the GUI rejects a hook event from a stale
    /// runtime after the socket layer has already registered it.
    public func cancelPending(toolUseId: String) {
        guard let pending = _pending.remove(toolUseId) else { return }
        pending.connection.cancel()
    }

    private static func removeStaleSocket(at path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
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
        lock.lock()
        dict[key] = value
        lock.unlock()
    }

    /// Inserts only if the key is absent, doing the check and set under one lock to avoid a TOCTOU.
    /// Returns true if inserted, false if an entry already existed and the insert was rejected.
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
        lock.lock()
        let v = dict.removeValue(forKey: key)
        lock.unlock()
        return v
    }

    func all() -> [(Key, Value)] {
        lock.lock()
        let items = Array(dict)
        lock.unlock()
        return items
    }

    /// Removes the entries matching `predicate` and returns the removed values.
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
        lock.lock()
        dict.removeAll()
        lock.unlock()
    }
}

/// Lock-guarded holder for a single value, so a `Sendable` class that cannot hold a mutable var
/// can still carry reference-type state such as a timer.
final class LockedBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()

    func set(_ newValue: T?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
