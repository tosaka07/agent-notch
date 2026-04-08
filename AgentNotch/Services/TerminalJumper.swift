import AppKit
import Foundation

/// Activates the terminal window running a given Claude session.
/// Handles direct terminal processes and tmux sessions.
enum TerminalJumper {

    @discardableResult
    @MainActor
    static func jump(pid: Int32?, tty: String?) -> Bool {
        // Strategy 1: PID tree walk
        if let pid, let app = findTerminalApp(forChildPID: pid) {
            app.activate()
            return true
        }

        // Strategy 2: TTY → tmux pane select + client TTY → PID tree walk
        if let tty {
            // Check if this TTY belongs to a tmux pane
            if let tmuxInfo = tmuxResolve(paneTTY: tty) {
                // Select the tmux window and pane first
                selectTmuxPane(target: tmuxInfo.paneTarget)

                if let app = findTerminalApp(forChildPID: tmuxInfo.clientPID) {
                    app.activate()
                    return true
                }
            }

            // Fallback: direct TTY lookup
            let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            if let pids = pidsForTTY(ttyName) {
                for p in pids {
                    if let app = findTerminalApp(forChildPID: p) {
                        app.activate()
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - PID tree walk

    private static func findTerminalApp(forChildPID childPID: Int32) -> NSRunningApplication? {
        let appPIDs = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { ($0.processIdentifier, $0) }
        )

        var currentPID = childPID
        for _ in 0..<15 {
            if let app = appPIDs[currentPID] { return app }
            let parent = parentPIDOf(currentPID)
            if parent <= 1 { break }
            currentPID = parent
        }
        return nil
    }

    // MARK: - tmux

    private struct TmuxInfo {
        let paneTarget: String  // e.g. "session:2.3"
        let clientPID: Int32
    }

    /// Given a pane TTY (e.g. /dev/ttys021), resolve the tmux pane target and client PID.
    private static func tmuxResolve(paneTTY tty: String) -> TmuxInfo? {
        // 1. Find which tmux session:window.pane owns this TTY
        let panes = runProcess("/usr/bin/env", args: [
            "tmux", "list-panes", "-a",
            "-F", "#{pane_tty} #{session_name}:#{window_index}.#{pane_index}",
        ])
        guard let targetLine = panes.split(separator: "\n")
            .first(where: { $0.hasPrefix(tty) || $0.hasPrefix(tty.replacingOccurrences(of: "/dev/", with: "")) })
        else { return nil }

        let paneTarget = targetLine.split(separator: " ").last.map(String.init) ?? ""
        let sessionName = paneTarget.split(separator: ":").first.map(String.init) ?? ""

        // 2. Find the client attached to this session
        let clients = runProcess("/usr/bin/env", args: [
            "tmux", "list-clients",
            "-F", "#{client_tty} #{client_pid} #{client_session}",
        ])
        for line in clients.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            if String(parts[2]) == sessionName, let pid = Int32(parts[1]) {
                return TmuxInfo(paneTarget: paneTarget, clientPID: pid)
            }
        }

        // 3. Fallback: any client
        if let firstLine = clients.split(separator: "\n").first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2, let pid = Int32(parts[1]) {
                return TmuxInfo(paneTarget: paneTarget, clientPID: pid)
            }
        }

        return nil
    }

    /// Select the tmux window and pane so the user sees the right one.
    private static func selectTmuxPane(target: String) {
        // target is "session:window.pane"
        let parts = target.split(separator: ".")
        let windowTarget = String(parts.first ?? Substring(target))  // "session:window"
        _ = runProcess("/usr/bin/env", args: ["tmux", "select-window", "-t", windowTarget])
        _ = runProcess("/usr/bin/env", args: ["tmux", "select-pane", "-t", target])
    }

    // MARK: - Helpers

    private static func pidsForTTY(_ ttyName: String) -> [Int32]? {
        let output = runProcess("/bin/ps", args: ["-t", ttyName, "-o", "pid="])
        let pids = output.split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        return pids.isEmpty ? nil : pids
    }

    private static func parentPIDOf(_ pid: Int32) -> Int32 {
        let output = runProcess("/bin/ps", args: ["-p", "\(pid)", "-o", "ppid="])
        return Int32(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func runProcess(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
