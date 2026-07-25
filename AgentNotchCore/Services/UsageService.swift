import Foundation

/// Claude / Codex の使用量取得をまとめるエントリポイント。
/// UI 側（`AgentNotch` ターゲット）は本 actor 経由でのみ使用量にアクセスする。
public actor UsageService {
    public static let shared = UsageService()

    private let claudeClient: ClaudeUsageClient

    public init(claudeClient: ClaudeUsageClient = .shared) {
        self.claudeClient = claudeClient
    }

    /// Claude / Codex 両方の最新スナップショットを取得する。
    /// 片方が取得できなくても、もう片方の結果は返す。
    public func refresh() async -> UsageSnapshot {
        async let claude = claudeClient.fetchUsage()
        let codex = CodexUsageParser.latestSnapshot()
        return UsageSnapshot(claude: await claude, codex: codex, fetchedAt: Date())
    }
}
