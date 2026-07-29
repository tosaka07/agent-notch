import Foundation
import Network

public enum CodexDesktopIPCError: LocalizedError {
    case unavailable
    case response(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Codex Desktop IPC is unavailable"
        case .response(let message): "Codex Desktop IPC returned an error: \(message)"
        case .timedOut: "Codex Desktop IPC timed out"
        }
    }
}

/// Compatibility adapter for Codex Desktop's local multi-window IPC.
///
/// Codex Desktop currently owns a private stdio App Server, so the official
/// control socket used by the CLI is not available for its active turns. The
/// desktop itself mirrors thread state to follower windows over this socket.
/// This adapter uses only that small follower boundary and is intentionally
/// isolated from the shared question model and official CLI transport.
public final class CodexDesktopIPCClient: @unchecked Sendable {
    public typealias SnapshotHandler =
        @Sendable (_ threadId: String, _ requests: [CodexUserInputRequest]) -> Void

    private struct PendingResponse {
        let continuation: CheckedContinuation<Void, any Error>
        let timeout: DispatchWorkItem
    }

    private let socketPath: String
    private let onSnapshot: SnapshotHandler
    private let queue = DispatchQueue(
        label: "com.agentnotch.codex-desktop-ipc",
        qos: .userInitiated
    )
    private let maximumFrameBytes = 256 * 1_024 * 1_024

    // Queue-confined state.
    private var started = false
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var clientId = "initializing-client"
    private var initializeRequestId: String?
    private var followedThreadIds = Set<String>()
    private var pendingResponses: [String: PendingResponse] = [:]
    private var reconnectWork: DispatchWorkItem?
    private var reconnectAttempt = 0

    public init(
        socketPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        onSnapshot: @escaping SnapshotHandler
    ) {
        let codexHome =
            environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(homeDirectory)/.codex"
        self.socketPath = socketPath ?? "\(codexHome)/ipc/ipc.sock"
        self.onSnapshot = onSnapshot
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !started else { return }
            started = true
            connect()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            started = false
            reconnectWork?.cancel()
            reconnectWork = nil
            disconnect()
        }
    }

    public func setFollowedThreadIds(_ ids: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            let removed = followedThreadIds.subtracting(ids)
            let added = ids.subtracting(followedThreadIds)
            followedThreadIds = ids
            guard clientId != Self.initializingClientId else { return }
            for id in removed {
                try? sendFollowing(threadId: id, following: false)
            }
            for id in added {
                try? sendFollowing(threadId: id, following: true)
            }
        }
    }

    public func submit(
        threadId: String,
        requestId: CodexRPCID,
        answers: [String: [String]]
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [weak self] in
                guard let self, clientId != Self.initializingClientId, connection != nil else {
                    continuation.resume(throwing: CodexDesktopIPCError.unavailable)
                    return
                }

                let transportRequestId = UUID().uuidString
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self,
                        let pending = pendingResponses.removeValue(forKey: transportRequestId)
                    else { return }
                    pending.continuation.resume(throwing: CodexDesktopIPCError.timedOut)
                }
                pendingResponses[transportRequestId] = PendingResponse(
                    continuation: continuation,
                    timeout: timeout
                )
                queue.asyncAfter(deadline: .now() + 10, execute: timeout)

                do {
                    let response =
                        CodexUserInputProtocol.response(
                            requestId: requestId,
                            answers: answers
                        )["result"] ?? [:]
                    try send([
                        "type": "request",
                        "requestId": transportRequestId,
                        "sourceClientId": clientId,
                        "version": 1,
                        "method": "thread-follower-submit-user-input",
                        "params": [
                            "conversationId": threadId,
                            "requestId": requestId.jsonValue,
                            "response": response,
                        ],
                    ])
                } catch {
                    timeout.cancel()
                    pendingResponses.removeValue(forKey: transportRequestId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func connect() {
        guard started, connection == nil else { return }
        let connection = NWConnection(
            to: .unix(path: socketPath),
            using: .tcp
        )
        self.connection = connection
        receiveBuffer.removeAll(keepingCapacity: true)
        clientId = Self.initializingClientId

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection else { return }
            switch state {
            case .ready:
                reconnectAttempt = 0
                do {
                    let requestId = UUID().uuidString
                    initializeRequestId = requestId
                    try send([
                        "type": "request",
                        "requestId": requestId,
                        "sourceClientId": Self.initializingClientId,
                        "version": 0,
                        "method": "initialize",
                        "params": ["clientType": "agent-notch"],
                    ])
                    receiveNext()
                } catch {
                    connectionFailed(error)
                }
            case .failed(let error):
                connectionFailed(error)
            case .cancelled:
                connectionFailed(CodexDesktopIPCError.unavailable)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self, weak connection] content, _, isComplete, error in
            guard let self, let connection, self.connection === connection else { return }
            if let content { receiveBuffer.append(content) }
            if let error {
                connectionFailed(error)
                return
            }

            do {
                while let message = try decodeFrame() {
                    try handle(message)
                }
            } catch {
                connectionFailed(error)
                return
            }

            if isComplete {
                connectionFailed(CodexDesktopIPCError.unavailable)
            } else {
                receiveNext()
            }
        }
    }

    private func decodeFrame() throws -> [String: Any]? {
        if receiveBuffer.startIndex != 0 {
            receiveBuffer = Data(receiveBuffer)
        }
        guard receiveBuffer.count >= 4 else { return nil }
        let length =
            Int(receiveBuffer[0])
            | (Int(receiveBuffer[1]) << 8)
            | (Int(receiveBuffer[2]) << 16)
            | (Int(receiveBuffer[3]) << 24)
        guard length > 0, length <= maximumFrameBytes else {
            throw CodexDesktopIPCError.response("invalid frame length")
        }
        guard receiveBuffer.count >= 4 + length else { return nil }
        let payload = Data(receiveBuffer[4..<(4 + length)])
        receiveBuffer.removeSubrange(..<(4 + length))
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw CodexDesktopIPCError.response("invalid JSON")
        }
        return object
    }

    private func handle(_ message: [String: Any]) throws {
        switch message["type"] as? String {
        case "response":
            try handleResponse(message)
        case "broadcast":
            try handleBroadcast(message)
        case "client-discovery-request":
            guard let requestId = message["requestId"] as? String else { return }
            try send([
                "type": "client-discovery-response",
                "requestId": requestId,
                "response": ["canHandle": false],
            ])
        default:
            break
        }
    }

    private func handleResponse(_ message: [String: Any]) throws {
        guard let requestId = message["requestId"] as? String else { return }
        if requestId == initializeRequestId {
            guard message["resultType"] as? String == "success",
                message["method"] as? String == "initialize",
                let result = message["result"] as? [String: Any],
                let assignedClientId = result["clientId"] as? String
            else {
                throw CodexDesktopIPCError.response(
                    message["error"] as? String ?? "initialize failed"
                )
            }
            initializeRequestId = nil
            clientId = assignedClientId
            for threadId in followedThreadIds {
                try sendFollowing(threadId: threadId, following: true)
            }
            Log.socket.info("Connected to Codex Desktop IPC")
            return
        }

        guard let pending = pendingResponses.removeValue(forKey: requestId) else { return }
        pending.timeout.cancel()
        if message["resultType"] as? String == "success" {
            pending.continuation.resume()
        } else {
            pending.continuation.resume(
                throwing: CodexDesktopIPCError.response(
                    message["error"] as? String ?? "request failed"
                )
            )
        }
    }

    private func handleBroadcast(_ message: [String: Any]) throws {
        guard let method = message["method"] as? String,
            let params = message["params"] as? [String: Any]
        else { return }

        switch method {
        case "thread-stream-state-changed":
            guard (message["version"] as? NSNumber)?.intValue == 11,
                params["hostId"] as? String == "local",
                let threadId = params["conversationId"] as? String,
                followedThreadIds.contains(threadId),
                let change = params["change"] as? [String: Any]
            else { return }

            if change["type"] as? String == "snapshot" {
                guard let state = change["conversationState"] as? [String: Any] else { return }
                let rawRequests = state["requests"] as? [[String: Any]] ?? []
                onSnapshot(
                    threadId,
                    rawRequests.compactMap(CodexUserInputProtocol.parseRequest)
                )
            } else if change["type"] as? String == "patches",
                patchesMayChangeRequests(change["patches"] as? [[String: Any]] ?? [])
            {
                // Re-announcing an already-followed thread makes the owner send
                // a fresh snapshot. This avoids depending on the desktop's
                // private patch implementation while keeping refreshes limited
                // to the small `requests` branch.
                try sendFollowing(threadId: threadId, following: true)
            }
        case "thread-stream-following-status-requested":
            for threadId in followedThreadIds {
                try sendFollowing(threadId: threadId, following: true)
            }
        case "client-status-changed":
            if params["status"] as? String == "connected" {
                for threadId in followedThreadIds {
                    try sendFollowing(threadId: threadId, following: true)
                }
            }
        default:
            break
        }
    }

    private func patchesMayChangeRequests(_ patches: [[String: Any]]) -> Bool {
        patches.contains { patch in
            guard let path = patch["path"] as? [Any] else { return true }
            guard let first = path.first else { return true }
            return first as? String == "requests"
        }
    }

    private func sendFollowing(threadId: String, following: Bool) throws {
        try send([
            "type": "broadcast",
            "method": "thread-stream-following-changed",
            "sourceClientId": clientId,
            "params": [
                "conversationId": threadId,
                "hostId": "local",
                "following": following,
            ],
            "version": 1,
        ])
    }

    private func send(_ object: [String: Any]) throws {
        guard let connection else { throw CodexDesktopIPCError.unavailable }
        let payload = try JSONSerialization.data(withJSONObject: object)
        guard payload.count <= maximumFrameBytes else {
            throw CodexDesktopIPCError.response("frame too large")
        }
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        connection.send(
            content: frame,
            completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                self?.queue.async { [weak self] in
                    self?.connectionFailed(error)
                }
            })
    }

    private func connectionFailed(_ error: any Error) {
        guard connection != nil else { return }
        Log.socket.debug("Codex Desktop IPC disconnected: \(error.localizedDescription)")
        disconnect()
        scheduleReconnect()
    }

    private func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        clientId = Self.initializingClientId
        initializeRequestId = nil
        for (_, pending) in pendingResponses {
            pending.timeout.cancel()
            pending.continuation.resume(throwing: CodexDesktopIPCError.unavailable)
        }
        pendingResponses.removeAll()
    }

    private func scheduleReconnect() {
        guard started, reconnectWork == nil else { return }
        reconnectAttempt += 1
        let delay = min(pow(2, Double(min(reconnectAttempt - 1, 5))), 30)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            reconnectWork = nil
            connect()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static let initializingClientId = "initializing-client"
}
