import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Exercises the transport against a real Unix socket.
///
/// `HerdrSocketClientTests` replaces the transport, which leaves the parts that only exist at the
/// syscall level — the write loop, `SO_NOSIGPIPE`, the newline framing, the connect deadline —
/// unverified. Those are what a herdr that stops mid-exchange runs into, so they are checked here
/// against a listener that behaves the way herdr's server does.
@Suite("herdr socket transport", .serialized)
struct HerdrSocketTransportTests {
    @Test("a request and its answer cross a real socket")
    func roundTripOverRealSocket() throws {
        let listener = try LineListener(answer: .line(#"{"id":"x","result":{"type":"pong"}}"#))
        defer { listener.stop() }

        let response = HerdrSocketClient.call(
            method: "pane.get",
            params: ["pane_id": "w6:p2"],
            socketPath: listener.socketPath
        )

        #expect(response == .result(["type": "pong"]))
        let request = try #require(listener.receivedLine())
        #expect(request.hasSuffix("\n"))
        let json =
            try JSONSerialization.jsonObject(with: Data(request.dropLast().utf8)) as? [String: Any]
            ?? [:]
        #expect(json["method"] as? String == "pane.get")
    }

    /// herdr closes the connection once it has answered, so the last record can arrive without the
    /// newline that would have separated it from another.
    @Test("an answer that ends with the connection is still read")
    func readsAnswerWithoutTrailingNewline() throws {
        let listener = try LineListener(answer: .unterminated(#"{"id":"x","result":{"type":"pong"}}"#))
        defer { listener.stop() }

        let response = HerdrSocketClient.call(
            method: "pane.get",
            params: ["pane_id": "w6:p2"],
            socketPath: listener.socketPath
        )

        #expect(response == .result(["type": "pong"]))
    }

    /// A server that goes away mid-exchange must cost the caller its answer and nothing else. Writing
    /// to a closed peer raises SIGPIPE, whose default action would take the whole app down — if this
    /// test crashes the process rather than failing, that is the regression.
    @Test("a server that closes without answering fails the call, not the process")
    func peerCloseDoesNotKillTheProcess() throws {
        let listener = try LineListener(answer: .closeImmediately)
        defer { listener.stop() }

        let response = HerdrSocketClient.call(
            method: "pane.focus",
            params: ["pane_id": "w6:p2"],
            socketPath: listener.socketPath
        )

        #expect(response == nil)
    }

    @Test("a path nothing is listening on resolves to nothing")
    func missingSocketReportsNothing() {
        let response = HerdrSocketClient.call(
            method: "pane.get",
            params: ["pane_id": "w6:p2"],
            socketPath: "/tmp/agent-notch-herdr-absent-\(UUID().uuidString).sock"
        )

        #expect(response == nil)
    }
}

// MARK: - Listener

/// A minimal stand-in for herdr's server: accepts one connection, reads the request line, and
/// answers the way the case under test needs.
private final class LineListener {
    enum Answer {
        case line(String)
        case unterminated(String)
        case closeImmediately
    }

    let socketPath: String
    private let descriptor: Int32
    private let queue = DispatchQueue(label: "herdr-test-listener")
    private let received = LineBox()

    init(answer: Answer) throws {
        socketPath = "/tmp/agent-notch-herdr-test-\(UUID().uuidString).sock"
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ListenerError.setupFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { path in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                _ = strcpy(UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self), path)
            }
        }
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(descriptor, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else { throw ListenerError.setupFailed }

        let listening = descriptor
        let box = received
        queue.async { [socketPath] in
            _ = socketPath
            let connection = accept(listening, nil, nil)
            guard connection >= 0 else { return }
            defer { close(connection) }

            if case .closeImmediately = answer { return }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let read = buffer.withUnsafeMutableBytes { recv(connection, $0.baseAddress!, $0.count, 0) }
            if read > 0 {
                box.set(String(decoding: buffer[0..<read], as: UTF8.self))
            }

            let payload: String =
                switch answer {
                case .line(let text): text + "\n"
                case .unterminated(let text): text
                case .closeImmediately: ""
                }
            _ = Array(payload.utf8).withUnsafeBytes {
                Darwin.send(connection, $0.baseAddress!, $0.count, 0)
            }
        }
    }

    func receivedLine() -> String? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let line = received.get() { return line }
            usleep(10_000)
        }
        return nil
    }

    func stop() {
        close(descriptor)
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private enum ListenerError: Error {
        case setupFailed
    }
}

/// The listener answers on its own queue, so the request it read crosses a thread boundary.
/// `SocketIntegrationTests` keeps an equivalent box to itself.
private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ line: String) {
        lock.lock()
        value = line
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
