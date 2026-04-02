import Foundation

enum HookInstaller {
    static let hookVersion = "1"

    nonisolated(unsafe) private static let hookEvents: [[String: Any]] = [
        ["event": "SessionStart"],
        ["event": "UserPromptSubmit"],
        ["event": "PreToolUse", "matcher": "*"],
        ["event": "PostToolUse", "matcher": "*"],
        ["event": "PostToolUseFailure", "matcher": "*"],
        ["event": "PermissionRequest", "matcher": "*", "timeout": 86400],
        ["event": "Notification", "matcher": "*"],
        ["event": "Stop"],
        ["event": "SubagentStop"],
        ["event": "SessionEnd"],
        ["event": "PreCompact", "matcher": "auto/manual"],
    ]

    static func installIfNeeded() {
        guard !isInstalled() else { return }
        install()
    }

    static func isInstalled() -> Bool {
        let settingsPath = settingsFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        guard let version = json["_agentNotchHookVersion"] as? String else {
            return false
        }
        return version == hookVersion
    }

    static func install() {
        let settingsPath = settingsFilePath()
        var settings: [String: Any] = [:]

        if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = existing
        }

        let scriptPath = bundledHookScriptPath()
        var hooks: [[String: Any]] = []

        for hookEvent in hookEvents {
            var entry: [String: Any] = [:]
            entry["type"] = "command"
            entry["command"] = "python3 \(scriptPath)"

            if let event = hookEvent["event"] as? String {
                entry["event"] = event
            }
            if let matcher = hookEvent["matcher"] as? String {
                entry["matcher"] = matcher
            }
            if let timeout = hookEvent["timeout"] as? Int {
                entry["timeout"] = timeout
            }

            hooks.append(entry)
        }

        settings["hooks"] = hooks
        settings["_agentNotchHookVersion"] = hookVersion

        // Ensure the .claude directory exists
        let claudeDir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: claudeDir,
            withIntermediateDirectories: true
        )

        if let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    static func bundledHookScriptPath() -> String {
        // Try app bundle first
        if let bundlePath = Bundle.main.path(forResource: "claude-hook", ofType: "py") {
            return bundlePath
        }

        // Fallback: ~/.agent-notch/claude-hook.py
        let fallbackDir = NSHomeDirectory() + "/.agent-notch"
        let fallbackPath = fallbackDir + "/claude-hook.py"

        // Copy from bundle resources if the fallback doesn't exist
        if !FileManager.default.fileExists(atPath: fallbackPath) {
            try? FileManager.default.createDirectory(
                atPath: fallbackDir,
                withIntermediateDirectories: true
            )

            // Try to copy from the bundle's resource
            if let bundleURL = Bundle.main.url(forResource: "claude-hook", withExtension: "py") {
                try? FileManager.default.copyItem(
                    at: bundleURL,
                    to: URL(fileURLWithPath: fallbackPath)
                )
                // Make executable
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: fallbackPath
                )
            }
        }

        return fallbackPath
    }

    private static func settingsFilePath() -> String {
        NSHomeDirectory() + "/.claude/settings.json"
    }
}
