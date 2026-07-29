import Foundation

/// State the user attached to a session. Tracked independently of agent events and
/// never overrides `session.status`.
///
/// - `pinned`: always sorted to the top of the session list.
/// - `muted`: suppresses sound, auto-expand, and NotchNotification.
/// - `titleDisplayPreference`: optionally prefers the latest user prompt over the agent-supplied
///   session title on this session's card.
/// - `markedDoneAt`: when the user marked "I'm done looking at this turn". The session counts
///                   as done only while `session.lastActivityAt <= markedDoneAt`, so new
///                   activity clears it automatically.
public enum SessionTitleDisplayPreference: String, Codable, Equatable, Sendable {
    /// Keep the agent-supplied session title as the card title.
    case sessionTitle
    /// Show the latest user prompt as the card title. This is useful when a single session moves
    /// on to a different task while its original agent title remains unchanged.
    case latestPrompt
}

public struct SessionUserState: Codable, Equatable, Sendable {
    public var pinned: Bool
    public var muted: Bool
    /// `nil` preserves the existing default: agent title first, then the app-level prompt fallback.
    public var titleDisplayPreference: SessionTitleDisplayPreference?
    public var markedDoneAt: Date?

    public init(
        pinned: Bool = false,
        muted: Bool = false,
        titleDisplayPreference: SessionTitleDisplayPreference? = nil,
        markedDoneAt: Date? = nil
    ) {
        self.pinned = pinned
        self.muted = muted
        self.titleDisplayPreference = titleDisplayPreference
        self.markedDoneAt = markedDoneAt
    }

    public static let empty = SessionUserState()

    /// Whether every field is at its default, meaning the entry can be dropped from persistence.
    public var isDefault: Bool {
        !pinned && !muted && titleDisplayPreference == nil && markedDoneAt == nil
    }
}

/// Return type of `SessionManager.groupedSessions(...)`.
public struct SessionGroup: Identifiable, Sendable {
    /// Key for `Identifiable`; unique per grouping axis.
    public let key: String
    public var id: String { key }
    /// Group title shown in the UI (e.g. "Claude Code", "Waiting").
    /// Empty string when `grouping == .none`.
    public let title: String
    public let sessions: [UnifiedSession]

    public init(key: String, title: String, sessions: [UnifiedSession]) {
        self.key = key
        self.title = title
        self.sessions = sessions
    }
}
