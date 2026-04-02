import Foundation
import Network

enum SocketProtocol {
    static func encode(_ object: Any) throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(jsonData.count)
        var data = Data(bytes: &length, count: 4)
        data.append(jsonData)
        return data
    }

    static func decode(_ data: Data) throws -> (message: [String: Any], bytesConsumed: Int)? {
        guard data.count >= 4 else { return nil }
        let length = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let totalNeeded = 4 + Int(length)
        guard data.count >= totalNeeded else { return nil }
        let jsonData = data[4..<totalNeeded]
        guard let dict = try JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any] else {
            throw SocketError.invalidJSON
        }
        return (dict, totalNeeded)
    }
}

enum SocketError: Error {
    case invalidJSON
    case connectionFailed
}

final class SocketConnection: Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue
    let onMessage: @Sendable ([String: Any]) -> [String: Any]?

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        onMessage: @escaping @Sendable ([String: Any]) -> [String: Any]?
    ) {
        self.connection = connection
        self.queue = queue
        self.onMessage = onMessage
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveMessage()
            case .failed, .cancelled:
                self?.connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    private func receiveMessage() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) {
            [weak self] content, _, isComplete, error in
            guard let self, let data = content else {
                self?.connection.cancel()
                return
            }

            do {
                if let result = try SocketProtocol.decode(data) {
                    let response = self.onMessage(result.message)
                    if let response {
                        let responseData = try SocketProtocol.encode(response)
                        self.connection.send(
                            content: responseData,
                            completion: .contentProcessed { _ in
                                self.connection.cancel()
                            }
                        )
                    } else {
                        let emptyResponse = try SocketProtocol.encode([:] as [String: String])
                        self.connection.send(
                            content: emptyResponse,
                            completion: .contentProcessed { _ in
                                self.connection.cancel()
                            }
                        )
                    }
                }
            } catch {
                self.connection.cancel()
            }

            if isComplete || error != nil {
                self.connection.cancel()
            }
        }
    }
}
