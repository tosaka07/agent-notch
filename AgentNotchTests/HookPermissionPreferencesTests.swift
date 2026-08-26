import Defaults
import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Hook permission preferences")
struct HookPermissionPreferencesTests {
    @Test("Claude Code permissions stay in Agent Notch by default and can be passed through")
    func claudeCodePreference() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = HookPermissionPreferences(defaults: defaults)

        #expect(!preferences.shouldPassThroughPermissions(agentType: "claude"))

        defaults.set(true, forKey: HookPermissionPreferences.claudeCodePassThroughKey)

        #expect(preferences.shouldPassThroughPermissions(agentType: "claude"))
    }

    @Test("Codex permission pass-through is independent from Claude Code")
    func codexPreference() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = HookPermissionPreferences(defaults: defaults)
        defaults.set(true, forKey: HookPermissionPreferences.claudeCodePassThroughKey)

        #expect(!preferences.shouldPassThroughPermissions(agentType: "codex"))

        defaults.set(true, forKey: HookPermissionPreferences.codexPassThroughKey)

        #expect(preferences.shouldPassThroughPermissions(agentType: "codex"))
        #expect(preferences.shouldPassThroughPermissions(agentType: "claude"))
    }

    @Test("App settings use the hook helper's shared preference keys")
    func appSettingKeysMatchHookHelper() {
        #expect(
            Defaults.Keys.claudeCodePermissionPassThrough.name
                == HookPermissionPreferences.claudeCodePassThroughKey
        )
        #expect(
            Defaults.Keys.codexPermissionPassThrough.name
                == HookPermissionPreferences.codexPassThroughKey
        )
        #expect(Defaults.Keys.claudeCodePermissionPassThrough.defaultValue == false)
        #expect(Defaults.Keys.codexPermissionPassThrough.defaultValue == false)
    }

    @Test("The production preference reader ignores unsupported agents")
    func unknownAgentDoesNotPassThrough() {
        let preferences = HookPermissionPreferences()

        #expect(!preferences.shouldPassThroughPermissions(agentType: "unsupported"))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "HookPermissionPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
