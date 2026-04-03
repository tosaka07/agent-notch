import Foundation

/// Manages Claude Code hook installation.
/// Hooks call `agent-notch hook` CLI binary, which forwards events to the socket.
public enum HookInstaller {
    private static let hookIdentifier = "agent-notch"

    private static let hookEvents: [(event: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, nil),
        ("UserPromptSubmit", nil, nil),
        ("PreToolUse", "", nil),
        ("PostToolUse", "", nil),
        ("PostToolUseFailure", "", nil),
        ("PermissionRequest", "", 86400),
        ("Notification", "", nil),
        ("Stop", nil, nil),
        ("StopFailure", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("SessionEnd", nil, nil),
        ("PreCompact", "auto", nil),
        ("PostCompact", nil, nil),
    ]

    /// Install hooks using the CLI binary path.
    /// Called from the GUI app on launch.
    public static func installIfNeeded() {
        let cliPath = findCLIPath()
        updateSettings(command: "\(cliPath) hook")
    }

    /// Install hooks from the CLI itself (uses own binary path).
    public static func installCLI() {
        let cliPath = CommandLine.arguments[0]
        updateSettings(command: "\(cliPath) hook")
    }

    /// Remove our hooks from settings.json
    public static func uninstall() {
        let settingsPath = settingsFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { isOurHookEntry($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        json["hooks"] = hooks.isEmpty ? nil : hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    public static func isInstalled() -> Bool {
        let settingsPath = settingsFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            if entries.contains(where: { isOurHookEntry($0) }) { return true }
        }
        return false
    }

    // MARK: - Private

    private static func isOurHookEntry(_ entry: [String: Any]) -> Bool {
        guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
        return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
    }

    private static func updateSettings(command: String) {
        let settingsPath = settingsFilePath()
        var settings: [String: Any] = [:]

        if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, matcher, timeout) in hookEvents {
            var hookCmd: [String: Any] = ["type": "command", "command": command]
            if let timeout { hookCmd["timeout"] = timeout }

            var matcherEntry: [String: Any] = ["hooks": [hookCmd]]
            if let matcher { matcherEntry["matcher"] = matcher }

            if var existingEntries = hooks[event] as? [[String: Any]] {
                // Remove any old version of our hook, then add current
                existingEntries.removeAll { isOurHookEntry($0) }
                existingEntries.append(matcherEntry)
                hooks[event] = existingEntries
            } else {
                hooks[event] = [matcherEntry]
            }
        }

        settings["hooks"] = hooks

        let claudeDir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    /// Find the CLI binary path. Checks common install locations.
    private static func findCLIPath() -> String {
        // 1. Adjacent to GUI app binary (same .build/debug/ dir)
        let appDir = (Bundle.main.executablePath ?? "").components(separatedBy: "/").dropLast().joined(separator: "/")
        let adjacentPath = appDir + "/agent-notch"
        if FileManager.default.fileExists(atPath: adjacentPath) {
            return adjacentPath
        }

        // 2. In PATH
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["agent-notch"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice
        if let _ = try? whichProcess.run() {
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty { return path }
        }

        // 3. Homebrew
        let brewPath = "/opt/homebrew/bin/agent-notch"
        if FileManager.default.fileExists(atPath: brewPath) { return brewPath }

        // 4. Fallback — assume it's in PATH
        return "agent-notch"
    }

    private static func settingsFilePath() -> String {
        NSHomeDirectory() + "/.claude/settings.json"
    }
}
