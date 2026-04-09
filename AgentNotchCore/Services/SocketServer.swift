import Foundation
import Network

public struct PendingSocketResponse: Sendable {
    public let sessionId: String
    public let toolUseId: String
    public let connection: NWConnection
    public let receivedAt: Date

    public init(sessionId: String, toolUseId: String, connection: NWConnection, receivedAt: Date) {
        self.sessionId = sessionId; self.toolUseId = toolUseId
        self.connection = connection; self.receivedAt = receivedAt
    }
}

public final class SocketServer: Sendable {
    public static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.agentnotch.socketserver", qos: .userInitiated)
    public let onMessage: @Sendable ([String: Any], NWConnection) -> [String: Any]?

    private let _connections = NWProtocolFramer.LockedArray<SocketConnection>()
    private let _pending = NWProtocolFramer.LockedDict<String, PendingSocketResponse>()

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

    public func respondToPermission(toolUseId: String, decision: String, reason: String?) {
        guard let pending = _pending.remove(toolUseId) else { return }
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": decision, "message": reason ?? ""]
            ]
        ]
        if let data = try? SocketProtocol.encode(response) {
            pending.connection.send(content: data, completion: .contentProcessed { _ in
                pending.connection.cancel()
            })
        }
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

// Thread-safe array helper scoped inside NWProtocolFramer for namespace
extension NWProtocolFramer {
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

        func all() -> [(Key, Value)] {
            lock.lock(); let items = Array(dict); lock.unlock(); return items
        }

        func removeAll() {
            lock.lock(); dict.removeAll(); lock.unlock()
        }
    }
}
