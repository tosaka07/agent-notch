import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Hook installer runtime separation")
struct HookInstallerTests {
    @Test("Production installs a stable command for every Codex event")
    func productionUsesStableCommand() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try HookInstaller.install(using: .production, homeDirectory: home)

        let codex = try readJSONObject(home.appendingPathComponent(".codex/hooks.json"))
        let codexCommands = hookCommands(in: codex).filter { $0.contains("agent-notch") }
        #expect(codexCommands.count == 11)
        #expect(Set(codexCommands) == ["agent-notch hook --agent codex"])
        #expect(codexCommands.allSatisfy { !$0.contains(".build/") })

        let claude = try readJSONObject(home.appendingPathComponent(".claude/settings.json"))
        let claudeCommands = hookCommands(in: claude).filter { $0.contains("agent-notch") }
        #expect(Set(claudeCommands) == ["agent-notch hook"])

        // Codex's config.toml is not touched at all: `features.hooks` no longer exists in current
        // Codex, which runs hooks by default and rewrites the file for its own state.
        #expect(
            !FileManager.default.fileExists(
                atPath: home.appendingPathComponent(".codex/config.toml").path
            )
        )
    }

    @Test("Development installs the exact build product with shell quoting")
    func developmentUsesExactExecutable() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let executable =
            home
            .appendingPathComponent("Build Products")
            .appendingPathComponent("agent-notch")
            .path

        try HookInstaller.install(
            using: .development(executablePath: executable),
            homeDirectory: home
        )

        let codex = try readJSONObject(home.appendingPathComponent(".codex/hooks.json"))
        let ownCommands = hookCommands(in: codex).filter { $0.contains("agent-notch") }
        #expect(Set(ownCommands) == ["'\(executable)' hook --agent codex"])
    }

    @Test("Development executable paths safely quote apostrophes")
    func developmentQuotesApostrophes() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let executable = "/tmp/O'Brien/agent-notch"

        try HookInstaller.install(
            using: .development(executablePath: executable),
            homeDirectory: home
        )

        let codex = try readJSONObject(home.appendingPathComponent(".codex/hooks.json"))
        let ownCommands = hookCommands(in: codex).filter { $0.contains("agent-notch") }
        #expect(
            Set(ownCommands)
                == ["'/tmp/O'\"'\"'Brien/agent-notch' hook --agent codex"]
        )
    }

    @Test("Installing production migrates development hooks and preserves unrelated hooks")
    func migrationPreservesUnrelatedHooks() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let codexDirectory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let existing: [String: Any] = [
            "description": "keep this metadata",
            "hooks": [
                "SessionStart": [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": "/usr/local/bin/unrelated-hook",
                            ]
                        ]
                    ],
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": "/tmp/dev/.build/debug/agent-notch hook --agent codex",
                            ]
                        ]
                    ],
                ],
                "Notification": [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": "/tmp/dev/.build/debug/agent-notch hook --agent codex",
                            ]
                        ]
                    ]
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(
            withJSONObject: existing,
            options: [.prettyPrinted, .sortedKeys]
        )
        try existingData.write(to: hooksURL)

        try HookInstaller.install(using: .production, homeDirectory: home)

        let installed = try readJSONObject(hooksURL)
        let commands = hookCommands(in: installed)
        #expect(commands.contains("/usr/local/bin/unrelated-hook"))
        #expect(commands.filter { $0 == "agent-notch hook --agent codex" }.count == 11)
        #expect(commands.allSatisfy { !$0.contains("/tmp/dev/.build/") })
        #expect(installed["description"] as? String == "keep this metadata")

        let hooks = installed["hooks"] as? [String: Any]
        #expect(hooks?["Notification"] == nil)
    }

    @Test("Repeated installation leaves an identical hooks file untouched")
    func repeatedInstallDoesNotRewrite() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let hooksURL = home.appendingPathComponent(".codex/hooks.json")

        try HookInstaller.install(using: .production, homeDirectory: home)
        let firstData = try Data(contentsOf: hooksURL)
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: hooksURL.path)
        let firstFileNumber = firstAttributes[.systemFileNumber] as? NSNumber

        try HookInstaller.install(using: .production, homeDirectory: home)
        let secondData = try Data(contentsOf: hooksURL)
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: hooksURL.path)
        let secondFileNumber = secondAttributes[.systemFileNumber] as? NSNumber

        #expect(secondData == firstData)
        #expect(secondFileNumber == firstFileNumber)
    }

    @Test("Installation status is false before install and true after every hook is installed")
    func installationStatusTracksCompleteInstallation() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(try !HookInstaller.isInstalled(using: .production, homeDirectory: home))

        try HookInstaller.install(using: .production, homeDirectory: home)

        #expect(try HookInstaller.isInstalled(using: .production, homeDirectory: home))
    }

    @Test("Installation status rejects a different runtime")
    func installationStatusChecksRuntime() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try HookInstaller.install(using: .production, homeDirectory: home)

        #expect(
            try !HookInstaller.isInstalled(
                using: .development(executablePath: "/tmp/debug/agent-notch"),
                homeDirectory: home
            )
        )
    }

    @Test("Installation status becomes false when one expected event is missing")
    func installationStatusRequiresEveryEvent() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try HookInstaller.install(using: .production, homeDirectory: home)

        let codexURL = home.appendingPathComponent(".codex/hooks.json")
        var codex = try readJSONObject(codexURL)
        var hooks = try #require(codex["hooks"] as? [String: Any])
        hooks["SessionEnd"] = nil
        codex["hooks"] = hooks
        try writeJSONObject(codex, to: codexURL)

        #expect(try !HookInstaller.isInstalled(using: .production, homeDirectory: home))
    }

    @Test("Invalid JSON roots fail with a descriptive path")
    func invalidJSONRoot() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let claudeDirectory = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data("[]".utf8).write(to: settingsURL)

        do {
            try HookInstaller.install(using: .production, homeDirectory: home)
            Issue.record("Expected invalid JSON to throw")
        } catch let error as HookInstallerError {
            #expect(
                error.errorDescription
                    == "Hook configuration is not a JSON object: \(settingsURL.path)"
            )
        }
    }

    @Test("Installing one agent leaves the other agent's configuration untouched")
    func perAgentInstallIsIsolated() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try HookInstaller.install(.claudeCode, using: .production, homeDirectory: home)

        #expect(try HookInstaller.isInstalled(.claudeCode, using: .production, homeDirectory: home))
        #expect(try !HookInstaller.isInstalled(.codex, using: .production, homeDirectory: home))
        // The Codex files were never created, so "off" means Codex does not call us at all.
        for target in HookInstaller.installationTargets(for: .codex, homeDirectory: home) {
            #expect(!FileManager.default.fileExists(atPath: target))
        }
        // The all-agents check is the AND of both, so it stays false.
        #expect(try !HookInstaller.isInstalled(using: .production, homeDirectory: home))
    }

    @Test("Removing one agent's hooks keeps the other agent installed")
    func perAgentUninstallIsIsolated() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try HookInstaller.install(using: .production, homeDirectory: home)

        try HookInstaller.uninstall(.codex, homeDirectory: home)

        #expect(try HookInstaller.isInstalled(.claudeCode, using: .production, homeDirectory: home))
        #expect(try !HookInstaller.isInstalled(.codex, using: .production, homeDirectory: home))

        let codex = try readJSONObject(home.appendingPathComponent(".codex/hooks.json"))
        #expect(hookCommands(in: codex).filter { $0.contains("agent-notch") }.isEmpty)

        // Reinstalling the removed agent brings it back without touching the other one.
        try HookInstaller.install(.codex, using: .production, homeDirectory: home)
        #expect(try HookInstaller.isInstalled(using: .production, homeDirectory: home))
    }

    @Test("A removed agent can be reinstalled while unrelated hooks survive both operations")
    func perAgentUninstallPreservesUnrelatedHooks() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSONObject(
            [
                "hooks": [
                    "Stop": [
                        ["hooks": [["type": "command", "command": "/usr/local/bin/unrelated-hook"]]]
                    ]
                ]
            ],
            to: settingsURL
        )

        try HookInstaller.install(.claudeCode, using: .production, homeDirectory: home)
        try HookInstaller.uninstall(.claudeCode, homeDirectory: home)

        let settings = try readJSONObject(settingsURL)
        #expect(hookCommands(in: settings) == ["/usr/local/bin/unrelated-hook"])
    }

    @Test("The disclosed installation targets are exactly the files an install writes")
    func installationTargetsMatchWhatIsWritten() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let targets = HookInstaller.installationTargets(homeDirectory: home)
        for target in targets {
            #expect(!FileManager.default.fileExists(atPath: target))
        }

        try HookInstaller.install(using: .production, homeDirectory: home)

        // Consent UI shows this list as "what will be written", so any file the installer
        // touches without being listed would be an undisclosed write.
        for target in targets {
            #expect(FileManager.default.fileExists(atPath: target))
        }
        let written = try FileManager.default
            .subpathsOfDirectory(atPath: home.path)
            .map { home.appendingPathComponent($0) }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            }
            .map(\.path)
        #expect(Set(written) == Set(targets))
    }

    @Test("Uninstall removes only Agent Notch hooks and preserves metadata")
    func uninstallPreservesUnrelatedHooks() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let root: [String: Any] = [
            "description": "keep this metadata",
            "hooks": [
                "SessionStart": [
                    [
                        "hooks": [
                            ["type": "command", "command": "agent-notch hook"]
                        ]
                    ],
                    [
                        "hooks": [
                            ["type": "command", "command": "/usr/local/bin/unrelated-hook"]
                        ]
                    ],
                ],
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": "agent-notch hook"]
                        ]
                    ]
                ],
            ],
        ]
        let claudeURL = home.appendingPathComponent(".claude/settings.json")
        let codexURL = home.appendingPathComponent(".codex/hooks.json")
        try writeJSONObject(root, to: claudeURL)
        try writeJSONObject(root, to: codexURL)

        try HookInstaller.uninstall(homeDirectory: home)

        for url in [claudeURL, codexURL] {
            let remaining = try readJSONObject(url)
            #expect(remaining["description"] as? String == "keep this metadata")
            #expect(hookCommands(in: remaining) == ["/usr/local/bin/unrelated-hook"])
            let hooks = remaining["hooks"] as? [String: Any]
            #expect(hooks?["Stop"] == nil)
        }
    }

    @Test("Uninstall is a no-op when settings files do not exist")
    func uninstallMissingFiles() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try HookInstaller.uninstall(homeDirectory: home)

        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path))
    }

    @Test("Codex's own config file is never written or required")
    func codexConfigIsLeftAlone() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let configURL = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = "[features]\njs_repl = false\n"
        try original.write(to: configURL, atomically: true, encoding: .utf8)

        try HookInstaller.install(using: .production, homeDirectory: home)

        // Untouched: `features.hooks` no longer exists in current Codex, which runs hooks by
        // default and rewrites this file for its own `[hooks.state]`.
        #expect(try String(contentsOf: configURL, encoding: .utf8) == original)
        // And not required either — the status comes from the hook entries. Checking the flag once
        // made this report "off" while Codex was calling every hook in hooks.json.
        #expect(try HookInstaller.isInstalled(.codex, using: .production, homeDirectory: home))
        #expect(try HookInstaller.isInstalled(using: .production, homeDirectory: home))
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-hook-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }

    private func hookCommands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.values.flatMap { value -> [String] in
            guard let matcherEntries = value as? [[String: Any]] else { return [] }
            return matcherEntries.flatMap { matcherEntry -> [String] in
                guard let handlers = matcherEntry["hooks"] as? [[String: Any]] else { return [] }
                return handlers.compactMap { $0["command"] as? String }
            }
        }
    }
}
