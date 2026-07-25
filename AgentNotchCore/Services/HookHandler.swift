import Foundation

/// CLI hook handler: reads JSON from stdin, forwards to Agent Notch socket.
///
/// 通常は fire-and-forget で即 exit（agent をブロックしない）。
/// ただし `PermissionRequest` と `PreToolUse:AskUserQuestion` のときだけは
/// socket から応答を待ち、受け取った JSON を stdout に書き出してから exit する。
/// これにより Claude Code が Agent Notch の GUI 入力を hook response として採用できる。
public enum HookHandler {
    private static let socketPath = "/tmp/agent-notch-\(NSUserName()).sock"
    /// send 用タイムアウト（fire-and-forget 経路）
    private static let sendTimeout: Int = 3
    /// fire-and-forget 経路で、サーバーが受信し終えるのを待つ上限。
    ///
    /// 通常は 1ms 程度で返る。ここで待たないとイベントが捨てられることがあるが
    /// （`waitForServerToConsume` 参照）、agent をブロックしてはいけないので短く保つこと。
    private static let consumeTimeoutMicroseconds: Int32 = 300_000
    /// recv 用タイムアウト（deferred 経路）。ユーザーが GUI で操作する時間を許容。
    /// これを超えると hook は pass-through で exit し、agent 側（ターミナル）の通常プロンプトに
    /// フォールバックする。伸ばすほど「notch を見ていないユーザー」のターミナルが無反応に見える
    /// 時間が延びるため、むやみに伸ばさないこと。GUI 側はこの値を質問バナーの残り時間表示と
    /// `SocketServer.pendingTTLSeconds` の基準として参照する。
    public static let recvTimeoutSeconds: Int = 120

    public static func run(agentType: String = "claude") {
        // Read all of stdin
        guard let inputData = FileHandle.standardInput.availableData as Data?,
              !inputData.isEmpty,
              var json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
            Log.hooks.error("Hook invoked but no valid JSON on stdin")
            exit(0)
        }

        let event = json["hook_event_name"] as? String ?? json["event"] as? String ?? "unknown"
        let session = json["session_id"] as? String ?? "?"
        Log.hooks.info("Hook event=\(event) agent=\(agentType) session=\(session)")

        // Add process info and agent type
        json["_pid"] = getppid()
        json["_tty"] = getTTY()
        json["_agent_type"] = agentType

        if shouldWaitForResponse(json: json) {
            Log.hooks.info("Waiting for GUI response (deferred) event=\(event)")
            if let response = sendAndWaitForResponse(json) {
                if let data = try? JSONSerialization.data(withJSONObject: response),
                   let jsonString = String(data: data, encoding: .utf8) {
                    Log.hooks.info("Got GUI response, emitting to stdout")
                    // Claude Code は stdout の JSON を hook response として解釈する
                    FileHandle.standardOutput.write(Data(jsonString.utf8))
                }
            } else {
                Log.hooks.error("No response or timeout; falling through as pass-through")
            }
            exit(0)
        }

        // Fire-and-forget: send to socket, don't wait for a meaningful response
        sendToSocket(json)
        // Exit with no stdout output = pass-through (agent continues normally)
    }

    // MARK: - Dispatch rules

    /// 応答を待つべき hook かどうか。
    /// - `PermissionRequest`: Claude Code 本体の tool 実行権限要求（approve/deny を返す）
    /// - `PreToolUse` かつ `tool_name == "AskUserQuestion"`: ユーザー回答を返す
    private static func shouldWaitForResponse(json: [String: Any]) -> Bool {
        let event = json["hook_event_name"] as? String ?? ""
        if event == "PermissionRequest" { return true }
        if event == "PreToolUse", (json["tool_name"] as? String) == "AskUserQuestion" {
            return true
        }
        return false
    }

    // MARK: - Socket I/O

    /// 送信して応答を受信する。deferred 経路。
    /// 応答 JSON が得られなければ nil（fallback pass-through）。
    private static func sendAndWaitForResponse(_ message: [String: Any]) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // send は短いタイムアウト。recv は長めに。
        var sendTv = timeval(tv_sec: sendTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTv, socklen_t(MemoryLayout<timeval>.size))
        var recvTv = timeval(tv_sec: recvTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTv, socklen_t(MemoryLayout<timeval>.size))

        guard connectSocket(fd: fd) else { return nil }
        guard sendPayload(fd: fd, message: message) else { return nil }
        return receiveResponse(fd: fd)
    }

    /// fire-and-forget 経路。応答は待たないが、**サーバーが読み取るまでは閉じない**。
    private static func sendToSocket(_ message: [String: Any]) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var tv = timeval(tv_sec: sendTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard connectSocket(fd: fd) else { return }
        guard sendPayload(fd: fd, message: message) else { return }
        waitForServerToConsume(fd: fd)
    }

    /// サーバーが受信して接続を閉じるのを待つ（最大 `consumeTimeoutMilliseconds`）。
    ///
    /// # なぜ待つ必要があるのか
    /// 送信直後に close すると、**カーネルバッファにデータが残っていても捨てられる**ことが
    /// ある。受信側は `NWConnection` の `.ready` 通知を待ってから receive を仕掛けるため、
    /// その前に FIN が届くと「読む前に接続が終わった」状態になり、イベントが黙って消える。
    /// 実測で 10 件中 4 件が失われていた（通知が出ない・状態が古いままになる原因）。
    ///
    /// サーバーは 1 メッセージを読み終えると接続を閉じるので、EOF を待てば受信は保証される。
    /// 通常は 1ms 程度で返る。応答を解釈しないので fire-and-forget の性質は変わらない
    /// （agent を待たせないという趣旨は、タイムアウトを十分短く取ることで守る）。
    private static func waitForServerToConsume(fd: Int32) {
        var tv = timeval(tv_sec: 0, tv_usec: consumeTimeoutMicroseconds)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var scratch = [UInt8](repeating: 0, count: 16)
        // 戻り値は見ない。0（EOF = サーバーが読んで閉じた）/ タイムアウト / エラーの
        // どれであっても、ここでできることは同じ（送るものは既に送った）。
        _ = scratch.withUnsafeMutableBytes { buffer in
            recv(fd, buffer.baseAddress!, buffer.count, 0)
        }
    }

    // MARK: - Low-level helpers

    private static func connectSocket(fd: Int32) -> Bool {
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
        guard connectResult == 0 else {
            Log.hooks.error("Socket connect failed, errno=\(errno)")
            return false
        }
        return true
    }

    /// 4-byte length prefix + JSON ペイロードを送る。
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

    /// 4-byte length prefix で区切られた JSON 応答を 1 つ読む。
    /// タイムアウトや short-read は nil。
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

    /// 指定バイト数を読み切るまで繰り返し recv する。
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
            let tty = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !tty.isEmpty, tty != "??", tty != "-" {
                return tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
            }
        } catch {}
        return nil
    }
}
