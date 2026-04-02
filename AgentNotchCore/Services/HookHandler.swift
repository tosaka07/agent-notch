import Foundation
import Network

/// CLI hook handler: reads JSON from stdin, forwards to Agent Notch socket, prints response.
/// This replaces the Python hook script entirely.
public enum HookHandler {
    private static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"
    private static let timeout: TimeInterval = 300 // 5 min for permission decisions

    public static func run() {
        // Read all of stdin
        guard let inputData = try? FileHandle.standardInput.availableData,
              !inputData.isEmpty,
              var json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
            exit(0)
        }

        // Add process info
        json["_pid"] = ProcessInfo.processInfo.processIdentifier
        json["_tty"] = getTTY()

        // Forward to socket
        guard let response = sendToSocket(json) else {
            // Socket not available — print empty JSON so Claude Code doesn't error
            print("{}")
            exit(0)
        }

        // Print response
        if let responseData = try? JSONSerialization.data(withJSONObject: response),
           let responseStr = String(data: responseData, encoding: .utf8) {
            print(responseStr)
        } else {
            print("{}")
        }
    }

    private static func sendToSocket(_ message: [String: Any]) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Set timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
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
        guard connectResult == 0 else { return nil }

        // Send: 4-byte length prefix + JSON (AeroSpace protocol)
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return nil }
        var length = UInt32(payload.count)
        var sendData = Data(bytes: &length, count: 4)
        sendData.append(payload)

        let sent = sendData.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!, sendData.count, 0)
        }
        guard sent == sendData.count else { return nil }

        // Receive: 4-byte length prefix + JSON
        var headerBuf = [UInt8](repeating: 0, count: 4)
        let headerRead = recv(fd, &headerBuf, 4, MSG_WAITALL)
        guard headerRead == 4 else { return nil }

        let responseLength = Data(headerBuf).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard responseLength > 0, responseLength < 1_000_000 else { return nil }

        var responseBuf = [UInt8](repeating: 0, count: Int(responseLength))
        let bodyRead = recv(fd, &responseBuf, Int(responseLength), MSG_WAITALL)
        guard bodyRead == Int(responseLength) else { return nil }

        let responseData = Data(responseBuf)
        return try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    }

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
            let tty = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !tty.isEmpty && tty != "??" && tty != "-" {
                return tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
            }
        } catch {}
        return nil
    }
}
