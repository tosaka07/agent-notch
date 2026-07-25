import Foundation

/// `api.anthropic.com/api/oauth/usage` を叩いて Claude Code の `/usage` 相当の
/// 使用率とリセット時刻を取得する。
///
/// # 注意（undocumented API）
/// このエンドポイントは非公式。以下を必ず守ること:
/// - 呼び出し間隔は 180 秒以上に保つ（aggressive rate limit があり、狭い間隔だと
///   429 が返り続けるようになる）。間隔の管理は呼び出し側（Coordinator）の責務。
/// - `User-Agent: claude-code/<version>` ヘッダーが無いと最初から 429 になる。
/// - Anthropic が予告なく仕様変更・廃止する可能性がある。
/// - 失敗（トークン取得不可・401・429・ネットワークエラー等）は全て静かに `nil` を返し、
///   UI 側は該当セクションを非表示にするだけに留める（エラー通知は出さない）。
public actor ClaudeUsageClient {
    public static let shared = ClaudeUsageClient()

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthBetaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.0.0"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchUsage() async -> ClaudeUsageSnapshot? {
        guard let token = ClaudeCredentialsStore.loadAccessToken() else {
            Log.hooks.debug("Claude usage: no OAuth token found, skipping fetch")
            return nil
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                Log.hooks.debug("Claude usage: unexpected status \(status)")
                return nil
            }
            return ClaudeUsageParser.parse(data: data)
        } catch {
            Log.hooks.debug("Claude usage: request failed: \(error.localizedDescription)")
            return nil
        }
    }
}
