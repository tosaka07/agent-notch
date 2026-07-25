import Foundation
import Network

public enum SocketProtocol {
    public static func encode(_ object: Any) throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(jsonData.count)
        var data = Data(bytes: &length, count: 4)
        data.append(jsonData)
        return data
    }

    public static func decode(_ data: Data) throws -> (message: [String: Any], bytesConsumed: Int)? {
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

public enum SocketError: Error {
    case invalidJSON
    case connectionFailed
}

public final class SocketConnection: Sendable {
    public let connection: NWConnection
    private let queue: DispatchQueue
    public let onMessage: @Sendable ([String: Any], NWConnection) -> [String: Any]?

    public init(
        connection: NWConnection,
        queue: DispatchQueue,
        onMessage: @escaping @Sendable ([String: Any], NWConnection) -> [String: Any]?
    ) {
        self.connection = connection
        self.queue = queue
        self.onMessage = onMessage
    }

    public func start() {
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

    public func cancel() {
        connection.cancel()
    }

    private func receiveMessage(buffer: Data = Data()) {
        // 1 メッセージが 1 回の receive で届くとは限らない（大きな tool_input — 例えば
        // Write の全文や plan を含む PermissionRequest — は 64KB を超え、複数チャンクに
        // 分かれて届く）。decode が「まだ足りない」（nil）を返す間はバッファに積み増して
        // receive を繰り返す。以前はここでリトライせず、分割されたメッセージが黙って
        // 破棄されて hook が recv timeout まで待ちぼうけになっていた。
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let content { accumulated.append(content) }

            guard error == nil else {
                self.connection.cancel()
                return
            }

            do {
                if let result = try SocketProtocol.decode(accumulated) {
                    let response = self.onMessage(result.message, self.connection)
                    if let response {
                        // Immediate response — send and close
                        let responseData = try SocketProtocol.encode(response)
                        self.connection.send(
                            content: responseData,
                            completion: .contentProcessed { _ in
                                self.connection.cancel()
                            }
                        )
                    }
                    // nil response = deferred (connection stays open for later response)
                } else if isComplete {
                    // 相手が閉じたのにメッセージが完結していない — 不完全な送信として破棄。
                    self.connection.cancel()
                } else {
                    receiveMessage(buffer: accumulated)
                }
            } catch {
                self.connection.cancel()
            }
        }
    }
}
