import Foundation

/// Manages hook installation for Claude Code and Codex CLI.
/// Hooks call `agent-notch hook` CLI binary, which forwards events to the socket.
public enum HookInstaller {
    private static let hookIdentifier = "agent-notch"

    // MARK: - Claude Code hooks (settings.json)

    private static let claudeHookEvents: [(event: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, nil),
        ("UserPromptSubmit", nil, nil),
        ("PreToolUse", "", nil),
        ("PostToolUse", "", nil),
        ("PostToolUseFailure", "", nil),
        ("Notification", "", nil),
        // PermissionRequest: tool 実行前の権限確認 + AskUserQuestion の両方がこの hook 経由で届く。
        // GUI での回答/承認を待つため timeout を 24h に伸ばす。
        ("PermissionRequest", "*", 86400),
        ("Stop", nil, nil),
        ("StopFailure", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("SessionEnd", nil, nil),
        ("PreCompact", "auto", nil),
        ("PostCompact", nil, nil),
        // Claude Code 2.1+ の first-class イベント
        ("TaskCreated", nil, nil),
        ("TaskCompleted", nil, nil),
        ("TeammateIdle", nil, nil),
    ]

    // MARK: - Codex CLI hooks (hooks.json)

    private static let codexHookEvents: [(event: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, nil),
        ("UserPromptSubmit", nil, nil),
        ("PreToolUse", "", nil),
        ("PostToolUse", "", nil),
        ("Stop", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("Notification", "", nil),
    ]

    /// Install hooks for all supported agents.
    /// Called from the GUI app on launch.
    public static func installIfNeeded() {
        let cliPath = findCLIPath()
        Log.hooks.info("Installing hooks, CLI path: \(cliPath)")
        updateClaudeSettings(command: "\(cliPath) hook")
        updateCodexHooks(command: "\(cliPath) hook --agent codex")
        ensureCodexHooksEnabled()
        Log.hooks.info("Hook installation complete")
    }

    /// Install hooks from the CLI itself (uses own binary path).
    public static func installCLI() {
        let cliPath = CommandLine.arguments[0]
        Log.hooks.info("Installing hooks from CLI, path: \(cliPath)")
        updateClaudeSettings(command: "\(cliPath) hook")
        updateCodexHooks(command: "\(cliPath) hook --agent codex")
        ensureCodexHooksEnabled()
        Log.hooks.info("CLI hook installation complete")
    }

    /// Remove our hooks from all agent settings.
    public static func uninstall() {
        Log.hooks.info("Uninstalling all hooks")
        uninstallClaude()
        uninstallCodex()
        Log.hooks.info("Hook uninstallation complete")
    }

    public static func isInstalled() -> Bool {
        let installed = isClaudeInstalled() || isCodexInstalled()
        Log.hooks.debug("Hook installed check: \(installed)")
        return installed
    }

    // MARK: - Claude Code

    private static func isClaudeInstalled() -> Bool {
        let path = claudeSettingsPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains(where: { isOurHookEntry($0) }) == true
        }
    }

    private static func uninstallClaude() {
        let path = claudeSettingsPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { isOurHookEntry($0) }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        json["hooks"] = hooks.isEmpty ? nil : hooks
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Codex CLI

    private static func isCodexInstalled() -> Bool {
        let path = codexHooksPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains(where: { isOurHookEntry($0) }) == true
        }
    }

    private static func uninstallCodex() {
        let path = codexHooksPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { isOurHookEntry($0) }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        json["hooks"] = hooks.isEmpty ? nil : hooks
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func updateCodexHooks(command: String) {
        updateHooksFile(path: codexHooksPath(), events: codexHookEvents, command: command)
    }

    private static func updateClaudeSettings(command: String) {
        updateHooksFile(path: claudeSettingsPath(), events: claudeHookEvents, command: command)
    }

    // MARK: - Private

    private static func isOurHookEntry(_ entry: [String: Any]) -> Bool {
        guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
        return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
    }

    /// Shared logic for writing hooks into a JSON settings file (Claude or Codex).
    private static func updateHooksFile(
        path: String,
        events: [(event: String, matcher: String?, timeout: Int?)],
        command: String
    ) {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for (event, matcher, timeout) in events {
            var hookCmd: [String: Any] = ["type": "command", "command": command]
            if let timeout { hookCmd["timeout"] = timeout }

            var matcherEntry: [String: Any] = ["hooks": [hookCmd]]
            if let matcher { matcherEntry["matcher"] = matcher }

            if var existingEntries = hooks[event] as? [[String: Any]] {
                existingEntries.removeAll { isOurHookEntry($0) }
                existingEntries.append(matcherEntry)
                hooks[event] = existingEntries
            } else {
                hooks[event] = [matcherEntry]
            }
        }

        root["hooks"] = hooks

        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
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

    private static func claudeSettingsPath() -> String {
        NSHomeDirectory() + "/.claude/settings.json"
    }

    private static func codexHooksPath() -> String {
        NSHomeDirectory() + "/.codex/hooks.json"
    }

    private static func codexConfigPath() -> String {
        NSHomeDirectory() + "/.codex/config.toml"
    }

    /// Ensure Codex hooks are enabled under `[features]` in ~/.codex/config.toml.
    /// Canonical flag name is `hooks = true`; `codex_hooks = true` is a deprecated alias.
    /// Preserves all existing content — only appends the canonical flag if neither is present,
    /// and never removes an existing `codex_hooks = true`.
    private static func ensureCodexHooksEnabled() {
        let path = codexConfigPath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        // 既に canonical (`hooks = true`) または deprecated alias (`codex_hooks = true`) が
        // あれば何もしない。
        let hasCanonical = content.range(
            of: #"(?<![a-zA-Z_])hooks\s*=\s*true"#, options: .regularExpression
        ) != nil
        let hasDeprecatedAlias = content.range(
            of: #"codex_hooks\s*=\s*true"#, options: .regularExpression
        ) != nil
        if hasCanonical || hasDeprecatedAlias {
            return
        }

        var lines = content.components(separatedBy: "\n")

        if let featIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            // Insert right after the [features] line
            lines.insert("hooks = true", at: featIdx + 1)
        } else {
            // No [features] section — append at end
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append("[features]")
            lines.append("hooks = true")
        }

        let updated = lines.joined(separator: "\n")
        try? updated.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
