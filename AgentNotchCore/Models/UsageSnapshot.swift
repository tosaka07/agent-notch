import Foundation

/// 単一の使用量ウィンドウ（例: セッション5時間枠、週次枠）。
/// Claude / Codex 共通で使う agent 非依存の表現。
public struct UsageWindow: Sendable, Equatable {
    /// 0〜100 の使用率。
    public let usedPercent: Double
    /// リセット予定時刻。取得できない場合は nil。
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Claude Code の `/usage` 相当のスナップショット。
/// `api.anthropic.com/api/oauth/usage`（undocumented）のレスポンスから得る。
public struct ClaudeUsageSnapshot: Sendable, Equatable {
    /// Current session（5 時間枠）
    public let session: UsageWindow?
    /// Current week (all models)（7 日枠）
    public let weekAllModels: UsageWindow?
    /// Current week (特定モデル、例: Opus/Fable)。モデル名は `weekModelLabel` に保持。
    public let weekModel: UsageWindow?
    public let weekModelLabel: String?

    public init(
        session: UsageWindow?,
        weekAllModels: UsageWindow?,
        weekModel: UsageWindow?,
        weekModelLabel: String?
    ) {
        self.session = session
        self.weekAllModels = weekAllModels
        self.weekModel = weekModel
        self.weekModelLabel = weekModelLabel
    }
}

/// Codex CLI の rate limit スナップショット。
/// rollout jsonl の `token_count` イベント（`rate_limits`）から得る。
public struct CodexUsageSnapshot: Sendable, Equatable {
    /// primary window（5 時間相当）
    public let primary: UsageWindow?
    /// secondary window（週次相当）
    public let secondary: UsageWindow?
    /// "plus" / "pro" / "business" など。usage-based プランでは各 window が nil になりうる。
    public let planType: String?

    public init(primary: UsageWindow?, secondary: UsageWindow?, planType: String?) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

/// UI に渡す集約スナップショット。取得できなかった agent は nil のまま。
public struct UsageSnapshot: Sendable, Equatable {
    public let claude: ClaudeUsageSnapshot?
    public let codex: CodexUsageSnapshot?
    public let fetchedAt: Date

    public init(claude: ClaudeUsageSnapshot?, codex: CodexUsageSnapshot?, fetchedAt: Date) {
        self.claude = claude
        self.codex = codex
        self.fetchedAt = fetchedAt
    }

    public static let empty = UsageSnapshot(claude: nil, codex: nil, fetchedAt: .distantPast)
}
