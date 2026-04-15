import Foundation

/// セッション一覧のソート軸。
/// デフォルトは `.latestActivity`。
public enum SessionSortOrder: String, Codable, CaseIterable, Sendable {
    /// 要介入度の高い順（permissionWaiting → error → toolRunning → ... → completed）。
    case urgency
    /// 最後に activity があった時刻の降順。
    case latestActivity
    /// 開始時刻の降順。
    case startedAt
    /// プロジェクト名のアルファベット順。
    case project

    public var label: String {
        switch self {
        case .urgency: "要介入順"
        case .latestActivity: "最終更新順"
        case .startedAt: "開始時刻順"
        case .project: "プロジェクト順"
        }
    }
}

/// セッション一覧のグループ化軸。
public enum SessionGrouping: String, Codable, CaseIterable, Sendable {
    /// グループ化しない（フラットなリスト）。
    case none
    /// ステータス別（Waiting / Running / Idle / Done）。
    case status
    /// プロジェクト別（originRepoName または cwd の basename）。
    case project
    /// エージェント種別（Claude Code / Codex / ...）。
    case agent

    public var label: String {
        switch self {
        case .none: "グループ化なし"
        case .status: "ステータス別"
        case .project: "プロジェクト別"
        case .agent: "エージェント別"
        }
    }
}
