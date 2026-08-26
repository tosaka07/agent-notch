import Foundation

enum HookResponseControl {
    static let respondInTerminalKey = "_agent_notch_respond_in_terminal"

    static func shouldEmitToAgent(_ response: [String: Any]) -> Bool {
        response[respondInTerminalKey] as? Bool != true
    }
}

enum HookInvocationInput {
    static func readAll(from handle: FileHandle) -> Data {
        handle.readDataToEndOfFile()
    }
}

/// CLI hook handler: reads JSON from stdin, forwards to Agent Notch socket.
///
/// Normally fire-and-forget: it exits immediately so the agent is never blocked.
/// Only for `PermissionRequest` and `PreToolUse:AskUserQuestion` does it wait for a response on
/// the socket, write the received JSON to stdout, and then exit. That is what lets Claude Code
/// and Codex take input from Agent Notch's GUI as the hook response.
public enum HookHandler {
    /// Send timeout for the fire-and-forget path.
    private static let sendTimeout: Int = 3
    /// Upper bound on waiting for the server to finish receiving, on the fire-and-forget path.
    ///
    /// Normally returns within about a millisecond. Not waiting here can drop events (see
    /// `waitForServerToConsume`), but the agent must not be blocked, so keep this short.
    private static let consumeTimeoutMicroseconds: Int32 = 300_000
    /// Recv timeout for the deferred path, allowing time for the user to act in the GUI.
    /// Past this the hook exits as a pass-through and the agent falls back to its normal terminal
    /// prompt. Raising it lengthens how long the terminal looks unresponsive to a user who is not
    /// watching the notch, so do not raise it casually. The GUI uses this value as the basis for
    /// the question banner's remaining-time display and for `SocketServer.pendingTTLSeconds`.
    public static let recvTimeoutSeconds: Int = 120

    public static func run(agentType: String = "claude") {
        let inputData = HookInvocationInput.readAll(from: .standardInput)
        if let output = handle(
            inputData: inputData,
            agentType: agentType,
            permissionPreferences: HookPermissionPreferences()
        ) {
            FileHandle.standardOutput.write(output)
        }
    }

    /// Handles one hook invocation without owning process lifetime or standard I/O.
    ///
    /// Fire-and-forget hooks return nil after the server has consumed the message.
    /// Deferred hooks return exactly the JSON bytes that the CLI should emit to the agent.
    public static func handle(
        inputData: Data,
        agentType: String = "claude",
        socketPath: String = SocketServer.socketPath,
        permissionPreferences: HookPermissionPreferences? = nil
    ) -> Data? {
        guard !inputData.isEmpty,
            var json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any]
        else {
            Log.hooks.error("Hook invoked but no valid JSON on stdin")
            return nil
        }

        let event = json["hook_event_name"] as? String ?? json["event"] as? String ?? "unknown"
        let session = json["session_id"] as? String ?? "?"
        Log.hooks.info("Hook event=\(event) agent=\(agentType) session=\(session)")

        if event == "PermissionRequest",
            (json["tool_name"] as? String) != "AskUserQuestion",
            permissionPreferences?.shouldPassThroughPermissions(agentType: agentType) == true
        {
            Log.hooks.info(
                "Passing permission request through to \(agentType) session=\(session)"
            )
            return nil
        }

        // Add process info and agent type
        json["_pid"] = getppid()
        json["_tty"] = getTTY()
        json["_agent_type"] = agentType

        if shouldWaitForResponse(json: json) {
            Log.hooks.info("Waiting for GUI response (deferred) event=\(event)")
            if let response = sendAndWaitForResponse(json, socketPath: socketPath) {
                if !HookResponseControl.shouldEmitToAgent(response) {
                    // Emit no hook decision. Codex then falls back to its native approval
                    // prompt, where options such as updating future permissions are available.
                    Log.hooks.info("GUI handed permission response back to the terminal")
                } else if let data = try? JSONSerialization.data(withJSONObject: response) {
                    Log.hooks.info("Got GUI response, emitting to stdout")
                    return data
                }
            } else {
                Log.hooks.error("No response or timeout; falling through as pass-through")
            }
            return nil
        }

        // Fire-and-forget: send to socket, don't wait for a meaningful response
        sendToSocket(json, socketPath: socketPath)
        // Exit with no stdout output = pass-through (agent continues normally)
        return nil
    }

    // MARK: - Dispatch rules

    /// Whether this hook should wait for a response.
    /// - `PermissionRequest`: Claude Code/Codex request to run a tool; returns approve/deny.
    /// - `PreToolUse` with `tool_name == "AskUserQuestion"`: returns the user's answer.
    private static func shouldWaitForResponse(json: [String: Any]) -> Bool {
        let event = json["hook_event_name"] as? String ?? ""
        if event == "PermissionRequest" { return true }
        if event == "PreToolUse", (json["tool_name"] as? String) == "AskUserQuestion" {
            return true
        }
        return false
    }

    // MARK: - Socket I/O

    /// Sends and waits for a response (the deferred path).
    /// Returns nil if no response JSON arrives, which falls back to a pass-through.
    private static func sendAndWaitForResponse(
        _ message: [String: Any],
        socketPath: String
    ) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Short timeout on send, long on recv.
        var sendTv = timeval(tv_sec: sendTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTv, socklen_t(MemoryLayout<timeval>.size))
        var recvTv = timeval(tv_sec: recvTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTv, socklen_t(MemoryLayout<timeval>.size))

        guard connectSocket(fd: fd, socketPath: socketPath) else { return nil }
        guard sendPayload(fd: fd, message: message) else { return nil }
        return receiveResponse(fd: fd)
    }

    /// The fire-and-forget path. No response is awaited, but the socket is **not closed until the server has read it**.
    private static func sendToSocket(_ message: [String: Any], socketPath: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var tv = timeval(tv_sec: sendTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard connectSocket(fd: fd, socketPath: socketPath) else { return }
        guard sendPayload(fd: fd, message: message) else { return }
        waitForServerToConsume(fd: fd)
    }

    /// Waits for the server to receive the message and close the connection (up to
    /// `consumeTimeoutMicroseconds`).
    ///
    /// # Why the wait is necessary
    /// Closing immediately after sending can **discard data still sitting in the kernel buffer**.
    /// The receiver only posts a receive after `NWConnection` reports `.ready`, so a FIN arriving
    /// before that leaves the connection finished before anything was read, and the event vanishes
    /// silently — measured at roughly 4 losses out of 10 sends, which showed up as missing
    /// notifications and stale state.
    ///
    /// The server closes the connection once it has read one message, so waiting for EOF
    /// guarantees delivery. This stays fire-and-forget — the response is never interpreted, and
    /// the promise not to block the agent is kept by holding the timeout short.
    private static func waitForServerToConsume(fd: Int32) {
        var tv = timeval(tv_sec: 0, tv_usec: consumeTimeoutMicroseconds)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var scratch = [UInt8](repeating: 0, count: 16)
        // The return value is ignored: whether it is 0 (EOF, meaning the server read and closed),
        // a timeout, or an error, there is nothing left to do — the message has already been sent.
        _ = scratch.withUnsafeMutableBytes { buffer in
            recv(fd, buffer.baseAddress!, buffer.count, 0)
        }
    }

    // MARK: - Low-level helpers

    private static func connectSocket(fd: Int32, socketPath: String) -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Log.hooks.error("Socket path is too long")
            return false
        }
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                _ = strcpy(UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self), ptr)
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            Log.hooks.error("Socket connect failed, errno=\(errno)")
            return false
        }
        return true
    }

    /// Sends a 4-byte length prefix followed by the JSON payload.
    private static func sendPayload(fd: Int32, message: [String: Any]) -> Bool {
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return false }
        var length = UInt32(payload.count)
        var sendData = Data(bytes: &length, count: 4)
        sendData.append(payload)
        let sent = sendData.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!, sendData.count, 0)
        }
        return sent == sendData.count
    }

    /// Reads one JSON response framed by a 4-byte length prefix.
    /// Returns nil on timeout or a short read.
    private static func receiveResponse(fd: Int32) -> [String: Any]? {
        var lengthBuf = [UInt8](repeating: 0, count: 4)
        let lenRead = lengthBuf.withUnsafeMutableBytes { ptr in
            recvAll(fd: fd, buffer: ptr.baseAddress!, length: 4)
        }
        guard lenRead == 4 else {
            Log.hooks.error("recv length prefix failed or timed out (read=\(lenRead))")
            return nil
        }
        let length = lengthBuf.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard length > 0, length < 10 * 1024 * 1024 else { return nil }

        var payload = [UInt8](repeating: 0, count: Int(length))
        let payloadRead = payload.withUnsafeMutableBytes { ptr in
            recvAll(fd: fd, buffer: ptr.baseAddress!, length: Int(length))
        }
        guard payloadRead == Int(length) else {
            Log.hooks.error("recv payload incomplete (read=\(payloadRead) expected=\(length))")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Repeats recv until the requested number of bytes has been read.
    private static func recvAll(fd: Int32, buffer: UnsafeMutableRawPointer, length: Int) -> Int {
        var total = 0
        while total < length {
            let remaining = length - total
            let ptr = buffer.advanced(by: total)
            let got = recv(fd, ptr, remaining, 0)
            if got <= 0 { return total }  // error / EOF / timeout
            total += got
        }
        return total
    }

    /// Discover the TTY of the parent process (the shell running Claude Code).
    private static func getTTY() -> String? {
        let ppid = getppid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(ppid)", "-o", "tty="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let tty =
                String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !tty.isEmpty, tty != "??", tty != "-" {
                return tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
            }
        } catch {}
        return nil
    }
}
