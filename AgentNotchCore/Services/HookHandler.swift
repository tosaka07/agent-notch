import Foundation

/// CLI hook handler: reads JSON from stdin, forwards to Agent Notch socket, exits immediately.
/// Must never block the calling agent (Claude Code / Codex).
public enum HookHandler {
    private static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"
    private static let socketTimeout: Int = 3 // seconds — fail fast, never block the agent

    public static func run(agentType: String = "claude") {
        // Read all of stdin
        guard let inputData = FileHandle.standardInput.availableData as Data?,
              !inputData.isEmpty,
              var json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
            exit(0)
        }

        // Add agent type (lightweight — no process spawning)
        json["_pid"] = getppid()
        json["_agent_type"] = agentType

        // Fire-and-forget: send to socket, don't wait for a meaningful response
        sendToSocket(json)

        // Exit with no stdout output = pass-through (agent continues normally)
    }

    private static func sendToSocket(_ message: [String: Any]) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        // Short send timeout — never block the agent
        var tv = timeval(tv_sec: socketTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
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
        guard connectResult == 0 else { return }

        // Send: 4-byte length prefix + JSON
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return }
        var length = UInt32(payload.count)
        var sendData = Data(bytes: &length, count: 4)
        sendData.append(payload)

        _ = sendData.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!, sendData.count, 0)
        }
        // Don't wait for response — close immediately after send.
        // The kernel buffer ensures the server receives the data.
    }
}
