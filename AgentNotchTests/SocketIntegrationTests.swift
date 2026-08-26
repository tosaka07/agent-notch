import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Unix socket integration", .serialized)
struct SocketIntegrationTests {
    @Test("A framed message reaches SocketServer and its response returns to the client")
    func requestResponseRoundTrip() throws {
        let socketPath = temporarySocketPath()
        let received = TestBox<[String: Any]>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                received.set(message)
                return ["ack": "ok"]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)

        let response = try send(
            ["hook_event_name": "SessionStart", "session_id": "integration-session"],
            to: socketPath
        )

        #expect(received.get()?["session_id"] as? String == "integration-session")
        #expect(response["ack"] as? String == "ok")
    }

    @Test("A fire-and-forget hook reaches the server with agent and process metadata")
    func hookHandlerForwardsFireAndForgetEvent() throws {
        let socketPath = temporarySocketPath()
        let received = TestBox<[String: Any]>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                received.set(message)
                return [:]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)
        let input = Data(
            #"{"hook_event_name":"SessionStart","session_id":"hook-session"}"#.utf8
        )

        let output = HookHandler.handle(
            inputData: input,
            agentType: "codex",
            socketPath: socketPath
        )

        #expect(output == nil)
        #expect(received.get()?["hook_event_name"] as? String == "SessionStart")
        #expect(received.get()?["session_id"] as? String == "hook-session")
        #expect(received.get()?["_agent_type"] as? String == "codex")
        #expect((received.get()?["_pid"] as? NSNumber)?.int32Value ?? 0 > 0)
    }

    @Test("Claude Code permission pass-through leaves the request entirely to Claude Code")
    func claudePermissionPassThroughSkipsAgentNotch() throws {
        let socketPath = temporarySocketPath()
        let received = TestBox<[String: Any]>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                received.set(message)
                return [:]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)

        let suiteName = "SocketIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: HookPermissionPreferences.claudeCodePassThroughKey)
        let preferences = HookPermissionPreferences(defaults: defaults)
        let input = Data(
            """
            {"hook_event_name":"PermissionRequest","session_id":"claude-session","tool_name":"Bash"}
            """.utf8
        )

        let output = HookHandler.handle(
            inputData: input,
            agentType: "claude",
            socketPath: socketPath,
            permissionPreferences: preferences
        )

        #expect(output == nil)
        #expect(received.get() == nil)
    }

    @Test("Claude Code question still reaches Agent Notch when permissions pass through")
    func claudeQuestionStillUsesAgentNotch() throws {
        let socketPath = temporarySocketPath()
        let received = TestBox<[String: Any]>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                received.set(message)
                return [HookResponseControl.respondInTerminalKey: true]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)

        let suiteName = "SocketIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: HookPermissionPreferences.claudeCodePassThroughKey)
        let preferences = HookPermissionPreferences(defaults: defaults)
        let input = Data(
            """
            {
              "hook_event_name":"PermissionRequest",
              "session_id":"claude-question-session",
              "tool_name":"AskUserQuestion",
              "tool_input":{"questions":[{"question":"Deploy?","options":[]}]}
            }
            """.utf8
        )

        let output = HookHandler.handle(
            inputData: input,
            agentType: "claude",
            socketPath: socketPath,
            permissionPreferences: preferences
        )

        #expect(output == nil)
        #expect(received.get()?["tool_name"] as? String == "AskUserQuestion")
    }

    @Test("Codex permission pass-through leaves the request entirely to Codex")
    func codexPermissionPassThroughSkipsAgentNotch() throws {
        let socketPath = temporarySocketPath()
        let received = TestBox<[String: Any]>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                received.set(message)
                return [:]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)

        let suiteName = "SocketIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: HookPermissionPreferences.codexPassThroughKey)
        let preferences = HookPermissionPreferences(defaults: defaults)
        let input = Data(
            """
            {"hook_event_name":"PermissionRequest","session_id":"codex-session","tool_name":"Bash"}
            """.utf8
        )

        let output = HookHandler.handle(
            inputData: input,
            agentType: "codex",
            socketPath: socketPath,
            permissionPreferences: preferences
        )

        #expect(output == nil)
        #expect(received.get() == nil)
    }

    @Test("Codex user-input questions still reach Agent Notch when permissions pass through")
    func codexQuestionStillUsesAgentNotch() throws {
        let socketPath = temporarySocketPath()
        let received = TestBox<[String: Any]>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                received.set(message)
                return [:]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)

        let suiteName = "SocketIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: HookPermissionPreferences.codexPassThroughKey)
        let preferences = HookPermissionPreferences(defaults: defaults)
        let input = Data(
            """
            {
              "hook_event_name":"PreToolUse",
              "session_id":"codex-question-session",
              "tool_name":"request_user_input"
            }
            """.utf8
        )

        let output = HookHandler.handle(
            inputData: input,
            agentType: "codex",
            socketPath: socketPath,
            permissionPreferences: preferences
        )

        #expect(output == nil)
        #expect(received.get()?["tool_name"] as? String == "request_user_input")
    }

    @Test("A pending permission decision returns through the original hook connection")
    func pendingPermissionRoundTrip() throws {
        let socketPath = temporarySocketPath()
        let serverReference = TestBox<SocketServer>()
        let deliveryResult = TestBox<Bool>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, connection in
                let pending = PendingSocketResponse(
                    kind: .permissionRequest,
                    sessionId: message["session_id"] as? String ?? "",
                    toolUseId: message["tool_use_id"] as? String ?? "",
                    connection: connection,
                    receivedAt: Date()
                )
                guard serverReference.get()?.addPending(pending) == true else {
                    return nil
                }
                deliveryResult.set(
                    serverReference.get()?.respondToPermission(
                        toolUseId: pending.toolUseId,
                        decision: "allow",
                        reason: "Approved in Agent Notch"
                    )
                )
                return nil
            }
        )
        serverReference.set(server)
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)
        let input = Data(
            """
            {"hook_event_name":"PermissionRequest","session_id":"permission-session","tool_use_id":"tool-1"}
            """.utf8
        )

        let output = try #require(
            HookHandler.handle(
                inputData: input,
                agentType: "claude",
                socketPath: socketPath
            )
        )
        let response = try #require(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let hookOutput = try #require(response["hookSpecificOutput"] as? [String: Any])
        let decision = try #require(hookOutput["decision"] as? [String: Any])

        #expect(deliveryResult.get() == true)
        #expect(hookOutput["hookEventName"] as? String == "PermissionRequest")
        #expect(decision["behavior"] as? String == "allow")
        #expect(decision["message"] as? String == "Approved in Agent Notch")
        #expect(server.respondToPermission(toolUseId: "tool-1", decision: "deny", reason: nil) == false)
    }

    @Test("Question answers preserve the original input schema on the deferred response")
    func pendingQuestionRoundTrip() throws {
        let socketPath = temporarySocketPath()
        let serverReference = TestBox<SocketServer>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, connection in
                let pending = PendingSocketResponse(
                    kind: .askUserQuestion,
                    sessionId: "question-session",
                    toolUseId: "question-1",
                    connection: connection,
                    receivedAt: Date(),
                    toolInput: JSONBox([
                        "questions": [
                            ["question": "Deploy?", "options": [["label": "Yes"], ["label": "No"]]]
                        ]
                    ])
                )
                guard serverReference.get()?.addPending(pending) == true else {
                    return nil
                }
                _ = serverReference.get()?.respondToAskQuestion(
                    toolUseId: pending.toolUseId,
                    answers: ["Deploy?": "Yes"]
                )
                return nil
            }
        )
        serverReference.set(server)
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)
        let input = Data(
            """
            {"hook_event_name":"PermissionRequest","session_id":"question-session","tool_use_id":"question-1"}
            """.utf8
        )

        let output = try #require(
            HookHandler.handle(inputData: input, socketPath: socketPath)
        )
        let response = try #require(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let hookOutput = try #require(response["hookSpecificOutput"] as? [String: Any])
        let decision = try #require(hookOutput["decision"] as? [String: Any])
        let updatedInput = try #require(decision["updatedInput"] as? [String: Any])
        let questions = try #require(updatedInput["questions"] as? [[String: Any]])
        let answers = try #require(updatedInput["answers"] as? [String: String])

        #expect(decision["behavior"] as? String == "allow")
        #expect(questions.first?["question"] as? String == "Deploy?")
        #expect(answers == ["Deploy?": "Yes"])
    }

    @Test("Terminal handoff closes the deferred socket without emitting hook output")
    func terminalHandoffRoundTrip() throws {
        let socketPath = temporarySocketPath()
        let serverReference = TestBox<SocketServer>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, connection in
                let pending = PendingSocketResponse(
                    kind: .permissionRequest,
                    sessionId: "terminal-session",
                    toolUseId: "terminal-1",
                    connection: connection,
                    receivedAt: Date()
                )
                guard serverReference.get()?.addPending(pending) == true else {
                    return nil
                }
                _ = serverReference.get()?.respondInTerminal(
                    toolUseId: pending.toolUseId
                )
                return nil
            }
        )
        serverReference.set(server)
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)
        let input = Data(
            """
            {"hook_event_name":"PermissionRequest","session_id":"terminal-session","tool_use_id":"terminal-1"}
            """.utf8
        )

        let output = HookHandler.handle(inputData: input, socketPath: socketPath)

        #expect(output == nil)
        #expect(server.respondInTerminal(toolUseId: "terminal-1") == false)
    }

    @Test("Messages larger than one receive chunk arrive without truncation")
    func largeMessageRoundTrip() throws {
        let socketPath = temporarySocketPath()
        let receivedLength = TestBox<Int>()
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { message, _ in
                receivedLength.set((message["tool_input"] as? String)?.utf8.count)
                return ["received": true]
            }
        )
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)
        let largeInput = String(repeating: "あ", count: 80_000)

        let response = try send(
            [
                "hook_event_name": "PreToolUse",
                "session_id": "large-session",
                "tool_input": largeInput,
            ],
            to: socketPath
        )

        #expect(receivedLength.get() == largeInput.utf8.count)
        #expect(response["received"] as? Bool == true)
    }

    @Test("Closing an unanswered hook connection expires its pending response")
    func disconnectedPendingExpires() throws {
        let socketPath = temporarySocketPath()
        let serverReference = TestBox<SocketServer>()
        let registered = TestBox<Bool>()
        let expired = TestBox<PendingSocketResponse>()
        let registrationSignal = DispatchSemaphore(value: 0)
        let expirationSignal = DispatchSemaphore(value: 0)
        let server = try SocketServer(
            socketPath: socketPath,
            onMessage: { _, connection in
                let pending = PendingSocketResponse(
                    kind: .permissionRequest,
                    sessionId: "expired-session",
                    toolUseId: "expired-tool",
                    connection: connection,
                    receivedAt: Date()
                )
                registered.set(serverReference.get()?.addPending(pending))
                registrationSignal.signal()
                return nil
            },
            onPendingExpired: { pending in
                expired.set(pending)
                expirationSignal.signal()
            }
        )
        serverReference.set(server)
        server.start()
        defer { server.stop() }
        try waitForSocket(at: socketPath)

        let descriptor = try sendLeavingConnectionOpen(
            ["hook_event_name": "PermissionRequest", "session_id": "expired-session"],
            to: socketPath
        )
        #expect(registrationSignal.wait(timeout: .now() + 2) == .success)
        close(descriptor)

        #expect(expirationSignal.wait(timeout: .now() + 2) == .success)
        #expect(registered.get() == true)
        #expect(expired.get()?.sessionId == "expired-session")
        #expect(expired.get()?.toolUseId == "expired-tool")
        #expect(
            server.respondToPermission(
                toolUseId: "expired-tool",
                decision: "allow",
                reason: nil
            ) == false
        )
    }

    private func temporarySocketPath() -> String {
        "/tmp/agent-notch-test-\(UUID().uuidString).sock"
    }

    private func waitForSocket(at path: String) throws {
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: path) {
            guard Date() < deadline else {
                throw IntegrationError.socketDidNotStart
            }
            usleep(10_000)
        }
    }

    private func send(_ message: [String: Any], to socketPath: String) throws -> [String: Any] {
        let descriptor = try connectedSocket(to: socketPath)
        defer { close(descriptor) }

        let request = try SocketProtocol.encode(message)
        guard writeAll(request, to: descriptor) else {
            throw IntegrationError.sendFailed
        }

        var buffer = Data()
        while true {
            if let decoded = try SocketProtocol.decode(buffer) {
                return decoded.message
            }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let count = chunk.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress!, $0.count, 0)
            }
            guard count > 0 else { throw IntegrationError.responseIncomplete }
            buffer.append(contentsOf: chunk.prefix(count))
        }
    }

    private func sendLeavingConnectionOpen(
        _ message: [String: Any],
        to socketPath: String
    ) throws -> Int32 {
        let descriptor = try connectedSocket(to: socketPath)
        let request = try SocketProtocol.encode(message)
        guard writeAll(request, to: descriptor) else {
            close(descriptor)
            throw IntegrationError.sendFailed
        }
        return descriptor
    }

    private func connectedSocket(to socketPath: String) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw IntegrationError.socketCreationFailed }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                _ = strcpy(
                    UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self),
                    source
                )
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard connected == 0 else {
            let connectionError = errno
            close(descriptor)
            throw IntegrationError.connectionFailed(connectionError)
        }
        return descriptor
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }
}

private enum IntegrationError: Error {
    case socketDidNotStart
    case socketCreationFailed
    case connectionFailed(Int32)
    case sendFailed
    case responseIncomplete
}

private final class TestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ newValue: Value?) {
        lock.withLock {
            value = newValue
        }
    }

    func get() -> Value? {
        lock.withLock {
            value
        }
    }
}
