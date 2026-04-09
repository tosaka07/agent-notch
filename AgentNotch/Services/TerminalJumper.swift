import AgentNotchCore
import AppKit
import Combine
import Foundation

/// Activates the terminal window running a given Claude session.
/// Handles direct terminal processes and tmux sessions (switch-client + select-window + select-pane).
enum TerminalJumper {

    @discardableResult
    @MainActor
    static func jump(pid: Int32?, tty: String?) -> Bool {
        Log.terminal.info("jump pid=\(pid.map(String.init) ?? "nil") tty=\(tty ?? "nil")")

        // Strategy 1: PID tree walk (non-tmux)
        if let pid, let app = findTerminalApp(forChildPID: pid) {
            Log.terminal.info("PID tree → \(app.localizedName ?? "?") (\(app.processIdentifier))")
            app.activate()
            closeNotch()
            return true
        }

        // Strategy 2: TTY → tmux resolution → switch-client + select + activate
        if let tty {
            if let tmuxInfo = tmuxResolve(paneTTY: tty) {
                Log.terminal.info("tmux pane=\(tmuxInfo.paneTarget) clientPID=\(tmuxInfo.clientPID)")
                selectTmuxPane(target: tmuxInfo.paneTarget)
                if let app = findTerminalApp(forChildPID: tmuxInfo.clientPID) {
                    Log.terminal.info("tmux client → \(app.localizedName ?? "?") (\(app.processIdentifier))")
                    app.activate()
                    closeNotch()
                    return true
                }
                Log.terminal.error("tmux client PID \(tmuxInfo.clientPID): no GUI app found")
            }

            // Fallback: direct TTY lookup
            let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            if let pids = pidsForTTY(ttyName) {
                for p in pids {
                    if let app = findTerminalApp(forChildPID: p) {
                        Log.terminal.info("TTY fallback → \(app.localizedName ?? "?") (\(app.processIdentifier))")
                        app.activate()
                        closeNotch()
                        return true
                    }
                }
            }
        }

        Log.terminal.error("all strategies failed")
        return false
    }

    private static func closeNotch() {
        NotificationCenter.default.post(name: .agentNotchClosePanel, object: nil)
    }

    // MARK: - Terminal Info Resolution

    struct TerminalInfo {
        let appName: String       // e.g. "iTerm2"
        let appIcon: NSImage?     // app icon
        let tmuxTarget: String?   // e.g. "main:2.1" or nil
    }

    /// Resolve terminal app and tmux info for a session. Call once and cache results.
    @MainActor
    static func resolveTerminalInfo(pid: Int32?, tty: String?) -> TerminalInfo? {
        // Try PID tree first
        if let pid, let app = findTerminalApp(forChildPID: pid) {
            let tmux = tty.flatMap { tmuxResolve(paneTTY: $0) }
            return TerminalInfo(
                appName: app.localizedName ?? "Terminal",
                appIcon: app.icon,
                tmuxTarget: tmux?.paneTarget
            )
        }

        // Try TTY → tmux
        if let tty, let tmux = tmuxResolve(paneTTY: tty) {
            if let app = findTerminalApp(forChildPID: tmux.clientPID) {
                return TerminalInfo(
                    appName: app.localizedName ?? "Terminal",
                    appIcon: app.icon,
                    tmuxTarget: tmux.paneTarget
                )
            }
        }

        // TTY fallback
        if let tty {
            let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            if let pids = pidsForTTY(ttyName) {
                for p in pids {
                    if let app = findTerminalApp(forChildPID: p) {
                        return TerminalInfo(
                            appName: app.localizedName ?? "Terminal",
                            appIcon: app.icon,
                            tmuxTarget: nil
                        )
                    }
                }
            }
        }

        return nil
    }

    /// Cached terminal icons by PID to avoid repeated PID tree walks on every render.
    @MainActor private static var iconCache: [Int32: NSImage] = [:]

    /// Get the app icon for a session's terminal. Cached after first lookup.
    @MainActor
    static func terminalIcon(pid: Int32?) -> NSImage? {
        guard let pid else { return nil }
        if let cached = iconCache[pid] { return cached }
        guard let icon = findTerminalApp(forChildPID: pid)?.icon else { return nil }
        iconCache[pid] = icon
        return icon
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

    private static func tmuxResolve(paneTTY tty: String) -> TmuxInfo? {
        let panes = runTmux([
            "list-panes", "-a",
            "-F", "#{pane_tty} #{session_name}:#{window_index}.#{pane_index}",
        ])
        guard let targetLine = panes.split(separator: "\n")
            .first(where: { $0.hasPrefix(tty) })
        else { return nil }

        let paneTarget = targetLine.split(separator: " ").last.map(String.init) ?? ""
        let sessionName = paneTarget.split(separator: ":").first.map(String.init) ?? ""

        let clients = runTmux([
            "list-clients",
            "-F", "#{client_tty} #{client_pid} #{client_session}",
        ])
        // Prefer client already attached to the same session
        for line in clients.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            if String(parts[2]) == sessionName, let pid = Int32(parts[1]) {
                return TmuxInfo(paneTarget: paneTarget, clientPID: pid)
            }
        }
        // Fallback: any client
        if let firstLine = clients.split(separator: "\n").first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2, let pid = Int32(parts[1]) {
                return TmuxInfo(paneTarget: paneTarget, clientPID: pid)
            }
        }
        return nil
    }

    private static func selectTmuxPane(target: String) {
        let sessionName = target.split(separator: ":").first.map(String.init) ?? ""
        let parts = target.split(separator: ".")
        let windowTarget = String(parts.first ?? Substring(target))

        _ = runTmux(["switch-client", "-t", sessionName])
        _ = runTmux(["select-window", "-t", windowTarget])
        _ = runTmux(["select-pane", "-t", target])
    }

    // MARK: - tmux path resolution

    private static let tmuxPath: String? = {
        // Resolve via login shell first (handles Nix, asdf, etc.)
        let shellResolved = runProcess("/bin/sh", args: ["-l", "-c", "which tmux"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !shellResolved.isEmpty, FileManager.default.isExecutableFile(atPath: shellResolved) {
            return shellResolved
        }
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static func runTmux(_ args: [String]) -> String {
        guard let tmux = tmuxPath else { return "" }
        return runProcess(tmux, args: args)
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
