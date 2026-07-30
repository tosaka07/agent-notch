import AgentNotchCore
import Defaults
import SwiftUI

enum CardPromptSource: String, Defaults.Serializable, CaseIterable, Sendable {
    case firstUserMessage
    case lastUserMessage

    var label: String {
        switch self {
        case .firstUserMessage: L("First prompt")
        case .lastUserMessage: L("Latest prompt")
        }
    }
}

// MARK: - Defaults conformance for Core types

extension SessionSortOrder: Defaults.Serializable {}
extension SessionGrouping: Defaults.Serializable {}
extension SessionUserState: Defaults.Serializable {}
extension AppLanguage: Defaults.Serializable {}

extension AppLanguage {
    var label: String {
        switch self {
        case .system: L("System Settings")
        case .english: "English"
        case .japanese: "日本語"
        }
    }
}

enum TextSizePreference: String, Defaults.Serializable, CaseIterable, Sendable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: L("Small")
        case .medium: L("Medium")
        case .large: L("Large")
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 1.0
        case .medium: 1.1
        case .large: 1.2
        }
    }

    /// Scale a base font size, rounding to nearest 0.5
    func scaled(_ base: CGFloat) -> CGFloat {
        (base * scale * 2).rounded() / 2
    }
}

enum SessionTimeoutPreference: Int, Defaults.Serializable, CaseIterable, Sendable {
    case oneHour = 3600
    case sixHours = 21600
    case oneDay = 86400
    case threeDays = 259200
    case never = 0

    var label: String {
        switch self {
        case .oneHour: L("1 hour")
        case .sixHours: L("6 hours")
        case .oneDay: L("1 day")
        case .threeDays: L("3 days")
        case .never: L("None")
        }
    }
}

enum NotificationTapAction: String, Defaults.Serializable, CaseIterable, Sendable {
    case jumpToTerminal
    case openSessionDetail

    var label: String {
        switch self {
        case .jumpToTerminal: L("Jump to terminal")
        case .openSessionDetail: L("Open session detail")
        }
    }
}

/// How the always-visible gauge at the left of the ExpandedPageView top bar is drawn.
///
/// Clicking the gauge itself opens the usage detail page, so switching the presentation
/// lives in settings rather than being a tap gesture.
enum UsageGaugeStyle: String, Defaults.Serializable, CaseIterable, Sendable {
    /// Ring only — a ring of dots showing the usage rate.
    case ring
    /// Number only — two pixel digits.
    case number

    var label: String {
        switch self {
        case .ring: L("Ring")
        case .number: L("Number")
        }
    }
}

/// Persists `UsageGaugeMetric` (which limit the gauge shows) as a setting.
///
/// The enum itself lives in `AgentNotchCore` next to its selection logic; Core does not
/// depend on Defaults, so only the `Defaults.Serializable` conformance is added here.
extension UsageGaugeMetric: Defaults.Serializable {}

extension UsageGaugeMetric {
    var label: String {
        switch self {
        case .auto: L("Auto (most constrained limit)")
        case .session: L("Session (5-hour limit)")
        case .weekly: L("Weekly (all models)")
        case .weeklyModel: L("Weekly (highest per model)")
        }
    }
}

enum DisplayModePreference: String, Defaults.Serializable, CaseIterable, Sendable {
    case followFocus
    case mainDisplay
    case builtinOnly
    case specificDisplay
    case allDisplays

    var label: String {
        switch self {
        case .followFocus: L("Display with pointer")
        case .mainDisplay: L("Main display")
        case .builtinOnly: L("Built-in display")
        case .specificDisplay: L("Specific display")
        case .allDisplays: L("All displays")
        }
    }
}

// MARK: - Sound

/// Represents a sound source: system sound, custom file, or none.
struct SoundChoice: Codable, Defaults.Serializable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case none
        case system  // /System/Library/Sounds/{name}.aiff
        case custom  // User-provided file path
    }

    var kind: Kind
    var name: String  // System sound name (e.g. "Glass") or custom file path

    static let none = SoundChoice(kind: .none, name: "")
    static func system(_ name: String) -> SoundChoice { SoundChoice(kind: .system, name: name) }
    static func custom(_ path: String) -> SoundChoice { SoundChoice(kind: .custom, name: path) }

    var displayName: String {
        switch kind {
        case .none: L("None")
        case .system: name
        case .custom: (name as NSString).lastPathComponent
        }
    }

    /// All available macOS system sounds.
    static let systemSounds: [String] = {
        let dir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return
            files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }()
}

/// Which events can trigger sounds.
enum SoundEvent: String, CaseIterable, Sendable {
    case sessionCompleted
    case subagentCompleted
    case permissionWaiting
    case question
    case error

    var label: String {
        switch self {
        case .sessionCompleted: L("Task completed")
        case .subagentCompleted: L("Subagent completed")
        case .permissionWaiting: L("Waiting for permission")
        case .question: L("Question")
        case .error: L("Error")
        }
    }

    var icon: String {
        switch self {
        case .sessionCompleted: "checkmark.circle"
        case .subagentCompleted: "person.2.circle"
        case .permissionWaiting: "exclamationmark.triangle"
        case .question: "questionmark.circle"
        case .error: "xmark.circle"
        }
    }
}

extension Defaults.Keys {
    /// Set only after the user explicitly authorizes hook installation and it succeeds.
    /// Until then, the onboarding window is the app's only usable surface.
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)

    /// Set once the onboarding tour has reached the consent page.
    ///
    /// A relaunch after that point means the disclosure was read and the install was declined,
    /// so the flow reopens on the stopped screen with a single recovery path instead of
    /// replaying the tour.
    static let hasReviewedHookConsent = Key<Bool>("hasReviewedHookConsent", default: false)

    /// Whether Agent Notch may touch Codex at all: its rollout logs, its app server, and the
    /// Desktop IPC channel.
    ///
    /// The Settings switch owns this together with the hook installation — one decision, "may this
    /// app work with Codex". `CodexAccessCoordinator` mirrors it into `CodexAccess` so Core's
    /// readers answer to the same flag, and reconciles it from the hooks on disk at launch so a
    /// hand-edited `hooks.json` cannot leave the two disagreeing.
    static let codexIntegrationEnabled = Key<Bool>("codexIntegrationEnabled", default: true)

    /// When enabled, the hook exits without taking ownership of ordinary permission requests so
    /// Claude Code can run its own approval flow. Questions remain routed through Agent Notch.
    static let claudeCodePermissionPassThrough = Key<Bool>(
        HookPermissionPreferences.claudeCodePassThroughKey,
        default: false,
        suite: UserDefaults(suiteName: HookPermissionPreferences.preferenceDomain) ?? .standard
    )

    /// When enabled, the hook exits without taking ownership of ordinary permission requests so
    /// Codex can run its own user or Auto-review flow. Questions remain routed through Agent Notch.
    static let codexPermissionPassThrough = Key<Bool>(
        HookPermissionPreferences.codexPassThroughKey,
        default: false,
        suite: UserDefaults(suiteName: HookPermissionPreferences.preferenceDomain) ?? .standard
    )

    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    static let textSize = Key<TextSizePreference>("textSize", default: .small)
    static let sessionTimeout = Key<SessionTimeoutPreference>("sessionTimeout", default: .oneDay)
    static let notificationTapAction = Key<NotificationTapAction>(
        "notificationTapAction", default: .jumpToTerminal)
    static let displayMode = Key<DisplayModePreference>("displayMode", default: .followFocus)
    /// UUID of the specific display chosen when displayMode == .specificDisplay
    static let specificDisplayUUID = Key<String>("specificDisplayUUID", default: "")

    // Sound settings per event
    static let soundCompleted = Key<SoundChoice>("soundCompleted", default: .system("Glass"))
    // Subagent completion fires constantly under parallel execution (5-16 at a time in a
    // workflow), so the default is silent. Pick a sound in settings to enable it.
    static let soundSubagentCompleted = Key<SoundChoice>("soundSubagentCompleted", default: .none)
    static let soundPermission = Key<SoundChoice>("soundPermission", default: .system("Funk"))
    static let soundQuestion = Key<SoundChoice>("soundQuestion", default: .system("Funk"))
    static let soundError = Key<SoundChoice>("soundError", default: .system("Basso"))
    static let soundEnabled = Key<Bool>("soundEnabled", default: true)

    // Session list sort / grouping
    static let sessionSortOrder = Key<SessionSortOrder>("sessionSortOrder", default: .latestActivity)
    static let sessionGrouping = Key<SessionGrouping>("sessionGrouping", default: .none)
    /// The set of collapsed group keys (each entry is a groupKey string).
    static let collapsedGroupIDs = Key<Set<String>>("collapsedGroupIDs", default: [])

    /// Per-session user state (pin/mute/title display/markedDoneAt), keyed by session ID.
    /// Synced from `SessionManager`'s change notifications; entries are removed when the
    /// session is.
    static let sessionUserStates = Key<[String: SessionUserState]>("sessionUserStates", default: [:])

    /// Which user prompt becomes the session-card title when the agent has no session title.
    static let cardPromptSource = Key<CardPromptSource>("cardPromptSource", default: .firstUserMessage)

    /// Presentation (ring / number) of the always-visible gauge at the left of the
    /// ExpandedPageView top bar.
    static let usageGaugeStyle = Key<UsageGaugeStyle>("usageGaugeStyle", default: .ring)

    /// Which limit (session / weekly / …) the always-visible gauge shows.
    static let usageGaugeMetric = Key<UsageGaugeMetric>("usageGaugeMetric", default: .auto)

    /// Whether the USAGE section at the bottom of ExpandedPageView is collapsed.
    /// Nothing reads this any more; the definition is kept so existing users' Defaults are
    /// not discarded for no reason.
    static let usageSectionCollapsed = Key<Bool>("usageSectionCollapsed", default: false)

    /// Whether to show usage (USAGE).
    ///
    /// Turning this off means never touching Claude's credentials or the undocumented API.
    /// It defaults to on. If a Keychain authorization dialog still appears in some
    /// environment, turning this off stops it completely.
    static let usageEnabled = Key<Bool>("usageEnabled", default: true)
}
