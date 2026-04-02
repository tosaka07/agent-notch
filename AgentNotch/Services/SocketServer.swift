import Foundation
import Network

final class SocketServer: Sendable {
    static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.agentnotch.socketserver", qos: .userInitiated)
    let onMessage: @Sendable ([String: Any]) -> [String: Any]?

    private let _connections = NWProtocolFramer.LockedArray<SocketConnection>()

    init(onMessage: @escaping @Sendable ([String: Any]) -> [String: Any]?) throws {
        self.onMessage = onMessage

        Self.removeStaleSocket()

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        self.listener = try NWListener(using: params)
    }

    func start() {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case let .failed(error):
                print("[SocketServer] listener failed: \(error)")
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

    func stop() {
        listener.cancel()
        for conn in _connections.removeAll() {
            conn.cancel()
        }
        Self.removeStaleSocket()
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
}
