import Foundation

enum HookInstaller {
    private static let hookScriptName = "agent-notch-hook.py"

    private static let hookEvents: [(event: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, nil),
        ("UserPromptSubmit", nil, nil),
        ("PreToolUse", "", nil),
        ("PostToolUse", "", nil),
        ("PostToolUseFailure", "", nil),
        ("PermissionRequest", "", 86400),
        ("Notification", "", nil),
        ("Stop", nil, nil),
        ("SubagentStop", nil, nil),
        ("SessionEnd", nil, nil),
        ("PreCompact", "auto", nil),
    ]

    static func installIfNeeded() {
        copyHookScript()
        updateSettings()
    }

    /// Remove our hooks from settings.json and delete the script
    static func uninstall() {
        let settingsPath = settingsFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { ($0["command"] as? String)?.contains(hookScriptName) == true }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        json["hooks"] = hooks.isEmpty ? nil : hooks
        json.removeValue(forKey: "_agentNotchHookVersion")

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }

        try? FileManager.default.removeItem(atPath: hookScriptInstallPath())
    }

    static func isInstalled() -> Bool {
        let settingsPath = settingsFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        // Check if any hook entry contains our script
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { continue }
                if entryHooks.contains(where: { ($0["command"] as? String)?.contains(hookScriptName) == true }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Private

    private static func updateSettings() {
        let settingsPath = settingsFilePath()
        var settings: [String: Any] = [:]

        if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        let scriptPath = hookScriptInstallPath()
        let command = "python3 \(scriptPath)"
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, matcher, timeout) in hookEvents {
            var hookCmd: [String: Any] = ["type": "command", "command": command]
            if let timeout { hookCmd["timeout"] = timeout }

            var matcherEntry: [String: Any] = ["hooks": [hookCmd]]
            if let matcher { matcherEntry["matcher"] = matcher }

            // Preserve existing hooks for this event — append ours if not already present
            if var existingEntries = hooks[event] as? [[String: Any]] {
                let alreadyInstalled = existingEntries.contains { entry in
                    guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                    return entryHooks.contains { ($0["command"] as? String)?.contains(hookScriptName) == true }
                }
                if !alreadyInstalled {
                    existingEntries.append(matcherEntry)
                    hooks[event] = existingEntries
                }
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

    private static func copyHookScript() {
        let installPath = hookScriptInstallPath()
        let installDir = (installPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: installDir, withIntermediateDirectories: true)

        // Always overwrite with latest version from bundle
        if let bundleURL = Bundle.main.url(forResource: "claude-hook", withExtension: "py") {
            try? FileManager.default.removeItem(atPath: installPath)
            try? FileManager.default.copyItem(at: bundleURL, to: URL(fileURLWithPath: installPath))
        } else {
            // Dev mode: copy from scripts/
            let devPath = (Bundle.main.bundlePath as NSString)
                .deletingLastPathComponent + "/scripts/claude-hook.py"
            if FileManager.default.fileExists(atPath: devPath) {
                try? FileManager.default.removeItem(atPath: installPath)
                try? FileManager.default.copyItem(
                    at: URL(fileURLWithPath: devPath),
                    to: URL(fileURLWithPath: installPath)
                )
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
    }

    private static func hookScriptInstallPath() -> String {
        NSHomeDirectory() + "/.agent-notch/\(hookScriptName)"
    }

    private static func settingsFilePath() -> String {
        NSHomeDirectory() + "/.claude/settings.json"
    }
}
