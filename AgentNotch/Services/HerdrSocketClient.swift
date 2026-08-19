import AgentNotchCore
import Foundation

/// Speaks herdr's control protocol over its Unix socket.
///
/// herdr exchanges newline-delimited JSON and closes the connection as soon as it has answered one
/// request, so every call here owns its own connection. The socket carries no authentication of its
/// own — filesystem permissions are the whole boundary — which is what lets an app that was never
/// started inside herdr drive it. cmux's own CLI refuses such callers, leaving Apple events as the
/// only way in (see `CmuxPaneJumper`); herdr needs no such detour.
///
/// Requests are built with `JSONSerialization`, so a pane identifier read out of a process
/// environment cannot break out of the value it is placed in.
enum HerdrSocketClient {
    /// The two shapes a response line can take.
    enum Response: Equatable {
        case result([String: String])
        case failure(code: String, message: String)
    }

    /// Sends one request line and returns the response line, or nil when the socket is unreachable.
    typealias Transport = (_ socketPath: String, _ requestLine: Data) -> Data?

    /// Long enough for a local server that is answering from memory, short enough that a herdr
    /// process wedged mid-answer does not hold up the jump it was asked about.
    private static let timeoutSeconds: Int = 1

    /// Responses this client asks for are single records. The cap only exists so a malformed stream
    /// cannot make the read grow without end.
    private static let maximumResponseBytes = 256 * 1024

    // MARK: - Calls

    /// Runs one method and reports what herdr answered.
    ///
    /// The `result` payload is flattened to its string values: everything this app asks herdr for is
    /// an identifier, and keeping the type shallow avoids threading `Any` through the callers.
    static func call(
        method: String,
        params: [String: String],
        socketPath: String,
        transport: Transport = sendLine
    ) -> Response? {
        guard let requestLine = requestLine(method: method, params: params) else { return nil }
        guard let responseLine = transport(socketPath, requestLine) else {
            Log.terminal.info("herdr: no answer from \(socketPath) for \(method)")
            return nil
        }
        return parse(responseLine: responseLine)
    }

    static func requestLine(
        method: String,
        params: [String: String],
        id: String = "agent-notch"
    ) -> Data? {
        let request: [String: Any] = ["id": id, "method": method, "params": params]
        guard var data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        data.append(0x0A)
        return data
    }

    static func parse(responseLine: Data) -> Response? {
        guard let json = try? JSONSerialization.jsonObject(with: responseLine) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any] {
            return .failure(
                code: error["code"] as? String ?? "unknown",
                message: error["message"] as? String ?? ""
            )
        }
        guard let result = json["result"] as? [String: Any] else { return nil }
        return .result(result.compactMapValues { $0 as? String })
    }

    // MARK: - Transport

    /// Connects, writes the line, and reads the single line herdr answers with.
    static func sendLine(socketPath: String, requestLine: Data) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard connectSocket(fd: fd, socketPath: socketPath) else { return nil }

        let sent = requestLine.withUnsafeBytes {
            Darwin.send(fd, $0.baseAddress!, requestLine.count, 0)
        }
        guard sent == requestLine.count else { return nil }

        return receiveLine(fd: fd)
    }

    private static func connectSocket(fd: Int32, socketPath: String) -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                _ = strcpy(UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self), ptr)
            }
        }
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    /// Reads up to the first newline, which is where one herdr record ends.
    private static func receiveLine(fd: Int32) -> Data? {
        var line = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while line.count < maximumResponseBytes {
            let read = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress!, $0.count, 0) }
            if read <= 0 { break }
            if let newline = chunk[0..<read].firstIndex(of: 0x0A) {
                line.append(contentsOf: chunk[0..<newline])
                return line
            }
            line.append(contentsOf: chunk[0..<read])
        }
        // A server that closed after a complete record without a trailing newline still answered.
        return line.isEmpty ? nil : line
    }
}
