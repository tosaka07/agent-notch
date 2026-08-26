import Foundation

public enum CodexSharedAppServerClientError: LocalizedError {
    case unavailable
    case launch(String)
    case rpc(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The shared Codex App Server is unavailable"
        case .launch(let message):
            "The shared Codex App Server connection failed: \(message)"
        case .rpc(let message):
            "The shared Codex App Server returned an error: \(message)"
        }
    }
}

/// Long-lived client for the official local Codex App Server daemon.
///
/// Recent Codex TUI releases can use the same daemon, so server-initiated
/// `item/tool/requestUserInput` requests are broadcast to both the TUI and
/// Agent Notch. Either surface may answer; `serverRequest/resolved` then keeps
/// the other surface synchronized.
///
/// `codex app-server proxy` is the documented transport adapter for the Unix
/// control socket. It carries a WebSocket byte stream over stdio, keeping
/// socket discovery and CODEX_HOME behavior owned by Codex.
///
/// This client intentionally does not start the daemon. The server's process
/// environment becomes the base environment for Codex tools, so launching it
/// from a Finder-started GUI could silently replace the user's terminal PATH,
/// SSH agent, proxy variables, or runtime-manager state. Users start the
/// managed daemon from their terminal before launching the TUI.
public final class CodexSharedAppServerClient: @unchecked Sendable {
    public typealias RequestHandler = @Sendable (CodexUserInputRequest) -> Void
    public typealias ResolvedHandler = @Sendable (CodexResolvedUserInput) -> Void
    public typealias ReadyHandler = @Sendable () -> Void

    private enum Phase {
        case handshaking(expectedAccept: String)
        case awaitingInitialization
        case ready
    }

    private enum ThreadSubscriptionOperation: Equatable {
        case resume
        case unsubscribe
    }

    private struct PendingThreadSubscription {
        let threadId: String
        let operation: ThreadSubscriptionOperation
    }

    private let executableURL: URL
    private let onRequest: RequestHandler
    private let onResolved: ResolvedHandler
    private let onReady: ReadyHandler
    private let queue = DispatchQueue(
        label: "com.agentnotch.codex-shared-app-server",
        qos: .userInitiated
    )
    private let maximumHandshakeBytes = 64 * 1_024

    // All fields below are confined to `queue`.
    private var started = false
    private var proxyProcess: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var phase: Phase?
    private var handshakeBuffer = Data()
    private var decoder = CodexWebSocketCodec.Decoder()
    private var connectionToken = UUID()
    private var reconnectWork: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var desiredThreadIds = Set<String>()
    private var loadedThreadIds = Set<String>()
    private var loadedListRequestId: String?
    private var subscribedThreadIds = Set<String>()
    private var pendingThreadSubscriptions: [String: PendingThreadSubscription] = [:]
    private var subscriptionRetryWork: DispatchWorkItem?

    public init(
        executableURL: URL,
        onRequest: @escaping RequestHandler,
        onResolved: @escaping ResolvedHandler,
        onReady: @escaping ReadyHandler = {}
    ) {
        self.executableURL = executableURL
        self.onRequest = onRequest
        self.onResolved = onResolved
        self.onReady = onReady
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !started else { return }
            started = true
            connectProxy()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            started = false
            reconnectWork?.cancel()
            reconnectWork = nil
            subscriptionRetryWork?.cancel()
            subscriptionRetryWork = nil
            closeProxy(sendClose: true)
        }
    }

    /// Subscribes this connection to the threads known through Codex hooks.
    ///
    /// `initialize` alone receives no thread-scoped server requests. App
    /// Server replays currently pending requests as part of `thread/resume`,
    /// which also keeps an Agent Notch restart from losing an open question.
    public func setFollowedThreadIds(_ ids: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            desiredThreadIds = ids
            guard case .ready = phase else { return }
            do {
                try refreshLoadedThreads()
            } catch {
                connectionFailed(error)
            }
        }
    }

    public func submit(
        requestId: CodexRPCID,
        answers: [String: [String]]
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [weak self] in
                guard let self, case .ready = phase else {
                    continuation.resume(throwing: CodexSharedAppServerClientError.unavailable)
                    return
                }
                do {
                    try sendJSON(CodexUserInputProtocol.response(requestId: requestId, answers: answers))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                    connectionFailed(error)
                }
            }
        }
    }

    private func connectProxy() {
        guard started, proxyProcess == nil else { return }
        // Most installations do not run the shared daemon. Avoid spawning a
        // short-lived proxy process every retry interval while its Unix socket
        // is absent; the reconnect timer doubles as a lightweight socket poll.
        guard FileManager.default.fileExists(atPath: Self.defaultControlSocketPath) else {
            scheduleReconnect()
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "proxy"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let token = UUID()
        connectionToken = token
        let outputReader = output.fileHandleForReading
        outputReader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                guard let self, connectionToken == token else { return }
                receive(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.queue.async { [weak self] in
                guard let self, connectionToken == token else { return }
                Log.socket.debug(
                    "Codex shared App Server proxy exited status=\(process.terminationStatus)"
                )
                connectionFailed(
                    CodexSharedAppServerClientError.launch(
                        "proxy exited with status \(process.terminationStatus)"
                    )
                )
            }
        }

        proxyProcess = process
        inputHandle = input.fileHandleForWriting
        outputHandle = outputReader
        handshakeBuffer.removeAll(keepingCapacity: true)
        decoder = CodexWebSocketCodec.Decoder()

        do {
            try process.run()
            let handshake = CodexWebSocketHandshake.makeRequest()
            phase = .handshaking(expectedAccept: handshake.expectedAccept)
            try inputHandle?.write(contentsOf: handshake.request)
        } catch {
            connectionFailed(CodexSharedAppServerClientError.launch(error.localizedDescription))
        }
    }

    private func receive(_ data: Data) {
        do {
            if case .handshaking(let expectedAccept) = phase {
                handshakeBuffer.append(data)
                guard handshakeBuffer.count <= maximumHandshakeBytes else {
                    throw CodexWebSocketError.invalidHandshake
                }
                guard
                    try CodexWebSocketHandshake.consumeResponse(
                        from: &handshakeBuffer,
                        expectedAccept: expectedAccept
                    )
                else { return }

                phase = .awaitingInitialization
                try sendJSON([
                    "id": Self.initializeRequestId,
                    "method": "initialize",
                    "params": [
                        "clientInfo": [
                            "name": "agent-notch",
                            "title": "Agent Notch",
                            "version": Self.clientVersion,
                        ],
                        "capabilities": [
                            "experimentalApi": true
                        ],
                    ],
                ])

                if !handshakeBuffer.isEmpty {
                    let remainder = handshakeBuffer
                    handshakeBuffer.removeAll(keepingCapacity: true)
                    try receiveFrames(remainder)
                }
                return
            }
            try receiveFrames(data)
        } catch {
            connectionFailed(error)
        }
    }

    private func receiveFrames(_ data: Data) throws {
        for message in try decoder.append(data) {
            switch message {
            case .text(let text):
                try processText(text)
            case .ping(let payload):
                try sendRaw(CodexWebSocketCodec.encodePong(payload))
            case .close:
                throw CodexWebSocketError.closed
            }
        }
    }

    private func processText(_ text: String) throws {
        guard let data = text.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CodexWebSocketError.invalidUTF8
        }

        if object["id"] as? String == Self.initializeRequestId {
            if let error = object["error"] as? [String: Any] {
                throw CodexSharedAppServerClientError.rpc(
                    error["message"] as? String ?? "initialize failed"
                )
            }
            guard object["result"] != nil else {
                throw CodexSharedAppServerClientError.rpc("initialize returned no result")
            }
            try sendJSON(["method": "initialized", "params": [:]])
            phase = .ready
            reconnectAttempt = 0
            Log.socket.info("Connected to shared Codex App Server")
            onReady()
            try refreshLoadedThreads()
            return
        }

        if let responseId = object["id"] as? String,
            responseId == loadedListRequestId
        {
            loadedListRequestId = nil
            if let error = object["error"] as? [String: Any] {
                Log.socket.debug(
                    "Codex loaded-thread query failed: \(error["message"] as? String ?? "unknown")"
                )
                scheduleSubscriptionRetry()
            } else if let result = object["result"] as? [String: Any],
                let ids = result["data"] as? [String]
            {
                loadedThreadIds = Set(ids)
                try synchronizeThreadSubscriptions()
                if !desiredThreadIds.isSubset(of: loadedThreadIds) {
                    scheduleSubscriptionRetry()
                }
            } else {
                Log.socket.debug("Codex loaded-thread query returned an invalid response")
                scheduleSubscriptionRetry()
            }
            return
        }

        if let responseId = object["id"] as? String,
            let pending = pendingThreadSubscriptions.removeValue(forKey: responseId)
        {
            if let error = object["error"] as? [String: Any] {
                Log.socket.debug(
                    "Codex thread subscription failed thread=\(pending.threadId) operation=\(String(describing: pending.operation)) error=\(error["message"] as? String ?? "unknown")"
                )
                scheduleSubscriptionRetry()
                return
            } else {
                switch pending.operation {
                case .resume:
                    subscribedThreadIds.insert(pending.threadId)
                case .unsubscribe:
                    subscribedThreadIds.remove(pending.threadId)
                }
            }
            try synchronizeThreadSubscriptions()
            return
        }

        if let request = CodexUserInputProtocol.parseRequest(object) {
            onRequest(request)
        } else if let resolved = CodexUserInputProtocol.parseResolved(object) {
            onResolved(resolved)
        }
    }

    private func refreshLoadedThreads() throws {
        guard case .ready = phase else { return }
        if desiredThreadIds.isEmpty {
            try synchronizeThreadSubscriptions()
            return
        }
        guard loadedListRequestId == nil else { return }

        let requestId = "agent-notch-loaded-\(UUID().uuidString)"
        loadedListRequestId = requestId
        do {
            try sendJSON([
                "id": requestId,
                "method": "thread/loaded/list",
                "params": [:],
            ])
        } catch {
            loadedListRequestId = nil
            throw error
        }
    }

    private func synchronizeThreadSubscriptions() throws {
        guard case .ready = phase else { return }
        let pendingThreadIds = Set(pendingThreadSubscriptions.values.map(\.threadId))
        // A rollout ID alone does not prove that the observed CLI is attached
        // to this daemon. Resuming an unloaded rollout could open the same
        // thread in a second process beside an embedded TUI. Only subscribe to
        // threads already loaded in this exact App Server process.
        let eligibleThreadIds = Self.eligibleThreadIds(
            desired: desiredThreadIds,
            loaded: loadedThreadIds
        )

        for threadId in eligibleThreadIds.subtracting(subscribedThreadIds)
        where !pendingThreadIds.contains(threadId) {
            try sendThreadSubscription(.resume, threadId: threadId)
        }
        for threadId in subscribedThreadIds.subtracting(eligibleThreadIds)
        where !pendingThreadIds.contains(threadId) {
            try sendThreadSubscription(.unsubscribe, threadId: threadId)
        }
    }

    private func sendThreadSubscription(
        _ operation: ThreadSubscriptionOperation,
        threadId: String
    ) throws {
        let requestId = "agent-notch-thread-\(UUID().uuidString)"
        pendingThreadSubscriptions[requestId] = PendingThreadSubscription(
            threadId: threadId,
            operation: operation
        )
        do {
            try sendJSON([
                "id": requestId,
                "method": operation == .resume ? "thread/resume" : "thread/unsubscribe",
                "params": ["threadId": threadId],
            ])
        } catch {
            pendingThreadSubscriptions.removeValue(forKey: requestId)
            throw error
        }
    }

    private func scheduleSubscriptionRetry() {
        guard started, subscriptionRetryWork == nil, case .ready = phase else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            subscriptionRetryWork = nil
            do {
                try refreshLoadedThreads()
            } catch {
                connectionFailed(error)
            }
        }
        subscriptionRetryWork = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func sendJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexWebSocketError.invalidUTF8
        }
        try sendRaw(CodexWebSocketCodec.encodeText(text))
    }

    private func sendRaw(_ data: Data) throws {
        guard let inputHandle, proxyProcess?.isRunning == true else {
            throw CodexSharedAppServerClientError.unavailable
        }
        try inputHandle.write(contentsOf: data)
    }

    private func connectionFailed(_ error: any Error) {
        Log.socket.debug("Codex shared App Server disconnected: \(error.localizedDescription)")
        closeProxy(sendClose: false)
        scheduleReconnect()
    }

    private func closeProxy(sendClose: Bool) {
        reconnectWork?.cancel()
        reconnectWork = nil
        subscriptionRetryWork?.cancel()
        subscriptionRetryWork = nil

        if sendClose, proxyProcess?.isRunning == true, phase != nil {
            try? sendRaw(CodexWebSocketCodec.encodeClose())
        }
        outputHandle?.readabilityHandler = nil
        proxyProcess?.terminationHandler = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        if proxyProcess?.isRunning == true {
            proxyProcess?.terminate()
        }
        proxyProcess = nil
        inputHandle = nil
        outputHandle = nil
        phase = nil
        handshakeBuffer.removeAll(keepingCapacity: true)
        decoder = CodexWebSocketCodec.Decoder()
        connectionToken = UUID()
        loadedThreadIds.removeAll()
        loadedListRequestId = nil
        subscribedThreadIds.removeAll()
        pendingThreadSubscriptions.removeAll()
    }

    private func scheduleReconnect() {
        guard started, reconnectWork == nil else { return }
        reconnectAttempt += 1
        let delay = min(pow(2, Double(min(reconnectAttempt - 1, 5))), 30)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            reconnectWork = nil
            connectProxy()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static let initializeRequestId = "agent-notch-initialize"

    private static var defaultControlSocketPath: String {
        let environment = ProcessInfo.processInfo.environment
        let codexHome =
            environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true).path
        return URL(fileURLWithPath: codexHome, isDirectory: true)
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock")
            .path
    }

    static func eligibleThreadIds(desired: Set<String>, loaded: Set<String>) -> Set<String> {
        desired.intersection(loaded)
    }

    private static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
