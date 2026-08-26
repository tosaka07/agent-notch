import SwiftUI

/// Destinations in the settings sidebar.
///
/// Stacking everything into one `Form` would run past 800pt tall and put the
/// lower items out of reach. Each destination therefore owns one focused pane,
/// selected from the native SwiftUI sidebar.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    enum IconColor: Hashable, Sendable {
        case gray
        case blue
        case orange
        case red
        case green
        case purple
        case indigo
    }

    /// Language, text size, which display to use.
    case general
    /// How the session list behaves.
    case sessions
    /// Agent hook installation.
    case hooks
    /// Notifications and sound. Both are about how completion is announced, so
    /// they share a pane.
    case notifications
    case usage
    /// A visual reference for the session-state glyphs shown in the notch.
    case glyphs
    case shortcuts
    /// Product identity, version, and bundled open-source license notices.
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("General")
        case .sessions: L("Sessions")
        case .hooks: L("Hooks")
        case .notifications: L("Notifications")
        case .usage: L("Usage")
        case .glyphs: L("Glyphs")
        case .shortcuts: L("Shortcuts")
        case .about: L("About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .sessions: "list.bullet"
        case .hooks: "point.3.connected.trianglepath.dotted"
        case .notifications: "bell"
        case .usage: "chart.bar"
        case .glyphs: "square.grid.3x3.fill"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }

    /// Matches the semantic color families used by macOS System Settings.
    var iconColor: IconColor {
        switch self {
        case .general, .about: .gray
        case .sessions: .blue
        case .hooks: .orange
        case .notifications: .red
        case .usage: .green
        case .glyphs: .purple
        case .shortcuts: .indigo
        }
    }
}

/// Groups destinations under source-list headings. General remains the
/// ungrouped first destination, matching StayUp's overview-first structure.
enum SettingsSidebarSection: CaseIterable, Identifiable, Sendable {
    case agent
    case displayAndNotifications
    case application

    var id: Self { self }

    var title: String {
        switch self {
        case .agent: L("Agent")
        case .displayAndNotifications: L("Display & Notifications")
        case .application: L("Application")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .agent: [.sessions, .hooks]
        case .displayAndNotifications: [.notifications, .usage, .glyphs]
        case .application: [.shortcuts, .about]
        }
    }
}

/// Shares the selected destination between the SwiftUI sidebar and content.
@Observable
@MainActor
final class SettingsSelection {
    var tab: SettingsTab = .general
}
