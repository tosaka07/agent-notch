import Foundation

/// Selects the executable identity persisted in agent hook configuration.
///
/// Production deliberately uses a stable command name supplied by the installer
/// (for example, a Homebrew Cask `binary` link). Development uses the exact
/// build product so local hook changes can be exercised without installing it.
public enum HookRuntime: Equatable, Sendable {
    case development(executablePath: String)
    case production

    fileprivate var executableCommand: String {
        switch self {
        case .development(let executablePath):
            return shellQuote(executablePath)
        case .production:
            return "agent-notch"
        }
    }
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

public enum HookInstallerError: LocalizedError {
    case invalidJSON(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let path):
            return "Hook configuration is not a JSON object: \(path)"
        }
    }
}

/// An agent whose configuration Agent Notch can install hooks into.
///
/// Deliberately narrower than `AgentType`: hooks exist for these two agents only, and a switch
/// over this enum cannot silently forget one the way a switch with a `default` would.
public enum HookAgent: String, CaseIterable, Sendable {
    case claudeCode
    case codex

    public var agentType: AgentType {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        }
    }
}

/// Manages hook installation for Claude Code and Codex CLI.
/// Hooks call `agent-notch hook` CLI binary, which forwards events to the socket.
///
/// # Codex writes one file
/// Only `~/.codex/hooks.json`. Earlier versions also wrote `[features] hooks = true` into
/// `config.toml`, for Codex builds that gated hooks behind a flag. That flag is gone — current
/// Codex (0.145.0) has no `features.hooks` and runs hooks by default — and Codex rewrites
/// `config.toml` for its own `[hooks.state]`, dropping keys it no longer knows. Writing it made
/// Agent Notch touch a file it had no reason to, and *requiring* it made the installed check
/// report "off" while Codex was calling every hook in `hooks.json`.
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
        // PermissionRequest carries both pre-tool permission checks and AskUserQuestion.
        // The timeout is raised to 24h so the hook can wait for an answer or approval in the GUI.
        ("PermissionRequest", "*", 86400),
        ("Stop", nil, nil),
        ("StopFailure", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("SessionEnd", nil, nil),
        ("PreCompact", "auto", nil),
        ("PostCompact", nil, nil),
        // First-class events introduced in Claude Code 2.1+
        ("TaskCreated", nil, nil),
        ("TaskCompleted", nil, nil),
        ("TeammateIdle", nil, nil),
    ]

    // MARK: - Codex CLI hooks (hooks.json)

    /// All 11 events Codex supports (`HookEventName` in `codex-rs/protocol`). Unlike Claude,
    /// there is no `Notification` or `PostToolUseFailure`.
    /// PermissionRequest stays open for an allow/deny decision from the notch. Returning no
    /// decision hands the request back to Codex's native terminal approval.
    private static let codexHookEvents: [(event: String, matcher: String?, timeout: Int?)] = [
        ("SessionStart", nil, nil),
        ("UserPromptSubmit", nil, nil),
        ("PreToolUse", "", nil),
        ("PostToolUse", "", nil),
        ("PermissionRequest", "", nil),
        ("Stop", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("SessionEnd", nil, nil),
        ("PreCompact", nil, nil),
        ("PostCompact", nil, nil),
    ]

    /// Every agent configuration file `install(using:)` writes, in write order.
    ///
    /// Exposed so consent UI can disclose the exact write targets instead of restating them —
    /// a second, hand-maintained list would eventually disagree with what is actually written.
    public static func installationTargets(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        HookAgent.allCases.flatMap { installationTargets(for: $0, homeDirectory: homeDirectory) }
    }

    /// The configuration files one agent's hooks live in, in write order.
    public static func installationTargets(
        for agent: HookAgent,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        switch agent {
        case .claudeCode:
            return [claudeSettingsPath(homeDirectory: homeDirectory)]
        case .codex:
            return [codexHooksPath(homeDirectory: homeDirectory)]
        }
    }

    /// Install hooks for all supported agents.
    ///
    /// The caller explicitly selects the runtime so launch context never changes
    /// the persisted command. Tests can redirect the complete installation to a
    /// temporary home directory through the same interface.
    public static func install(
        using runtime: HookRuntime,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        for agent in HookAgent.allCases {
            try install(agent, using: runtime, homeDirectory: homeDirectory)
        }
    }

    /// Install hooks for one agent, leaving the other agent's configuration untouched.
    ///
    /// Per-agent installation is what makes the Settings switches honest: turning Codex off has
    /// to mean "Codex no longer calls Agent Notch", not "Agent Notch ignores Codex while its
    /// config still runs our command on every event".
    public static func install(
        _ agent: HookAgent,
        using runtime: HookRuntime,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let command = hookCommand(for: agent, using: runtime)
        Log.hooks.info("Installing \(agent.rawValue) hooks, command: \(command)")
        switch agent {
        case .claudeCode:
            try updateClaudeSettings(
                command: command,
                path: claudeSettingsPath(homeDirectory: homeDirectory)
            )
        case .codex:
            try updateCodexHooks(
                command: command,
                path: codexHooksPath(homeDirectory: homeDirectory)
            )
        }
        Log.hooks.info("Hook installation complete for \(agent.rawValue)")
    }

    /// Whether every supported Claude Code and Codex event points at this runtime.
    ///
    /// This is intentionally stricter than looking for any Agent Notch command. A stale
    /// installation should be offered a reinstall when a new event is added or the runtime
    /// changes between development and production.
    public static func isInstalled(
        using runtime: HookRuntime,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Bool {
        for agent in HookAgent.allCases {
            guard try isInstalled(agent, using: runtime, homeDirectory: homeDirectory) else {
                return false
            }
        }
        return true
    }

    /// Whether one agent's every event points at this runtime.
    public static func isInstalled(
        _ agent: HookAgent,
        using runtime: HookRuntime,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Bool {
        let command = hookCommand(for: agent, using: runtime)
        switch agent {
        case .claudeCode:
            return try hooksFileContainsAllEvents(
                path: claudeSettingsPath(homeDirectory: homeDirectory),
                events: claudeHookEvents,
                command: command
            )
        case .codex:
            return try hooksFileContainsAllEvents(
                path: codexHooksPath(homeDirectory: homeDirectory),
                events: codexHookEvents,
                command: command
            )
        }
    }

    /// The exact command persisted for one agent.
    ///
    /// Codex trusts a hash of the complete hook definition. Exposing the canonical command lets
    /// the trust inspector match only Agent Notch's hooks instead of attributing another
    /// application's changed hook to this integration.
    public static func hookCommand(for agent: HookAgent, using runtime: HookRuntime) -> String {
        switch agent {
        case .claudeCode:
            return "\(runtime.executableCommand) hook"
        case .codex:
            return "\(runtime.executableCommand) hook --agent codex"
        }
    }

    /// Remove our hooks from all agent settings.
    public static func uninstall(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        Log.hooks.info("Uninstalling all hooks")
        for agent in HookAgent.allCases {
            try uninstall(agent, homeDirectory: homeDirectory)
        }
        Log.hooks.info("Hook uninstallation complete")
    }

    /// Remove our hooks for one agent.
    ///
    /// Only entries whose command is ours are removed, so unrelated hooks the user configured
    /// themselves survive. Codex's `[features] hooks = true` is deliberately left in place: it is
    /// a Codex-wide switch that other tools may rely on, and it does nothing on its own once our
    /// entries are gone.
    public static func uninstall(
        _ agent: HookAgent,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        Log.hooks.info("Uninstalling \(agent.rawValue) hooks")
        switch agent {
        case .claudeCode:
            try uninstallHooksFile(path: claudeSettingsPath(homeDirectory: homeDirectory))
        case .codex:
            try uninstallHooksFile(path: codexHooksPath(homeDirectory: homeDirectory))
        }
    }

    private static func uninstallHooksFile(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.invalidJSON(path: path)
        }
        guard var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { isOurHookEntry($0) }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        json["hooks"] = hooks.isEmpty ? nil : hooks
        let updated = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try writeIfChanged(updated, to: path)
    }

    // MARK: - Codex CLI

    private static func updateCodexHooks(command: String, path: String) throws {
        try updateHooksFile(path: path, events: codexHookEvents, command: command)
    }

    private static func updateClaudeSettings(command: String, path: String) throws {
        try updateHooksFile(path: path, events: claudeHookEvents, command: command)
    }

    // MARK: - Private

    private static func isOurHookEntry(_ entry: [String: Any]) -> Bool {
        guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
        return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
    }

    private static func hooksFileContainsAllEvents(
        path: String,
        events: [(event: String, matcher: String?, timeout: Int?)],
        command: String
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.invalidJSON(path: path)
        }
        guard let hooks = root["hooks"] as? [String: Any] else { return false }

        return events.allSatisfy { specification in
            guard let matcherEntries = hooks[specification.event] as? [[String: Any]] else {
                return false
            }
            return matcherEntries.contains { matcherEntry in
                guard let handlers = matcherEntry["hooks"] as? [[String: Any]] else {
                    return false
                }
                return handlers.contains { $0["command"] as? String == command }
            }
        }
    }

    /// Shared logic for writing hooks into a JSON settings file (Claude or Codex).
    private static func updateHooksFile(
        path: String,
        events: [(event: String, matcher: String?, timeout: Int?)],
        command: String
    ) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path) {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookInstallerError.invalidJSON(path: path)
            }
            root = existing
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // Strip our own entries from every event first, so that revising the event list does not
        // leave behind entries for events we no longer subscribe to (e.g. Notification, which
        // Codex does not have).
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { isOurHookEntry($0) }
            hooks[event] = entries.isEmpty ? nil : entries
        }

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
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try writeIfChanged(data, to: path)
    }

    private static func writeIfChanged(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        if (try? Data(contentsOf: url)) == data {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    private static func claudeSettingsPath(homeDirectory: URL) -> String {
        homeDirectory.appendingPathComponent(".claude/settings.json").path
    }

    private static func codexHooksPath(homeDirectory: URL) -> String {
        homeDirectory.appendingPathComponent(".codex/hooks.json").path
    }

}
