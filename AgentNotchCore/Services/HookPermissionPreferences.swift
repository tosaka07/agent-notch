import Foundation

/// Reads the Agent Notch preferences that control whether permission hooks are handled by
/// Agent Notch or passed through to the originating agent.
public struct HookPermissionPreferences {
    public static let preferenceDomain = "com.agentnotch.app"
    public static let claudeCodePassThroughKey = "claudeCodePermissionPassThrough"
    public static let codexPassThroughKey = "codexPermissionPassThrough"

    private let defaults: UserDefaults

    /// Uses the GUI app's explicit preference domain because the hook helper runs as a separate
    /// command-line executable and therefore has a different `UserDefaults.standard` domain.
    public init() {
        defaults = UserDefaults(suiteName: Self.preferenceDomain) ?? .standard
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func shouldPassThroughPermissions(agentType: String) -> Bool {
        switch agentType {
        case "claude":
            defaults.bool(forKey: Self.claudeCodePassThroughKey)
        case "codex":
            defaults.bool(forKey: Self.codexPassThroughKey)
        default:
            false
        }
    }
}
