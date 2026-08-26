import Foundation

/// Sort axis for the session list. Defaults to `.latestActivity`.
public enum SessionSortOrder: String, Codable, CaseIterable, Sendable {
    /// Most in need of attention first (permissionWaiting, error, toolRunning, ..., completed).
    case urgency
    /// Descending by the time of the last activity.
    case latestActivity
    /// Descending by start time.
    case startedAt
    /// Alphabetical by project name.
    case project

    public var label: String {
        switch self {
        case .urgency: AppLocalization.localized("By urgency")
        case .latestActivity: AppLocalization.localized("By last update")
        case .startedAt: AppLocalization.localized("By start time")
        case .project: AppLocalization.localized("By project")
        }
    }
}

/// Grouping axis for the session list.
public enum SessionGrouping: String, Codable, CaseIterable, Sendable {
    /// No grouping (flat list).
    case none
    /// By status (Waiting / Running / Idle / Done).
    case status
    /// By project (originRepoName, or the basename of cwd).
    case project
    /// By agent type (Claude Code / Codex / ...).
    case agent
    /// By agent-teams team; sessions without a `teamName` land in the "NO TEAM" bucket.
    case team

    public var label: String {
        switch self {
        case .none: AppLocalization.localized("No grouping")
        case .status: AppLocalization.localized("Group by status")
        case .project: AppLocalization.localized("Group by project")
        case .agent: AppLocalization.localized("Group by agent")
        case .team: AppLocalization.localized("Group by team")
        }
    }
}
