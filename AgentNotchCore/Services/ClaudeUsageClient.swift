import Foundation

/// Calls `api.anthropic.com/api/oauth/usage` to obtain the usage percentages and reset times
/// that Claude Code's `/usage` shows.
///
/// # Caution: undocumented API
/// This endpoint is unofficial. The following must be respected:
/// - Keep at least 180 seconds between calls. The rate limit is aggressive, and a tighter interval
///   makes it return 429 continuously. Pacing is the caller's (the Coordinator's) responsibility.
/// - Without a `User-Agent: claude-code/<version>` header it returns 429 from the first call.
/// - Anthropic may change or remove it without notice.
/// - No failure (no token, 401, 429, network error, ...) ever raises an error notification. Each
///   is reported as a `UsageUnavailableReason` so the gauge can stay on screen and say why it is
///   empty, rather than disappearing.
public actor ClaudeUsageClient {
    public static let shared = ClaudeUsageClient()

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthBetaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.0.0"

    private let session: URLSession
    private let credentials: ClaudeCredentialsProvider

    public init(session: URLSession = .shared, credentials: ClaudeCredentialsProvider = .shared) {
        self.session = session
        self.credentials = credentials
    }

    /// Convenience for callers that only care whether usage arrived.
    public func fetchUsage() async -> ClaudeUsageSnapshot? {
        guard case .success(let snapshot) = await fetch() else { return nil }
        return snapshot
    }

    public func fetch() async -> ClaudeUsageFetch {
        // The token is cached by `ClaudeCredentialsProvider`; the Keychain is not re-read on
        // every 180-second poll.
        let token: String
        switch await credentials.tokenState() {
        case .valid(let value):
            token = value
        case .expired:
            // Not an error to report loudly: Claude Code refreshes the token on its next run,
            // and the UI says exactly that.
            Log.hooks.debug("Claude usage: token expired, skipping fetch")
            return .unavailable(.tokenExpired)
        case .unavailable:
            Log.hooks.debug("Claude usage: no OAuth token found, skipping fetch")
            return .unavailable(.notSignedIn)
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
                // The token may have expired or been rotated, so drop the cache and re-read on the
                // next poll rather than retrying immediately.
                if status == 401 || status == 403 {
                    await credentials.invalidate()
                    return .unavailable(.unauthorized)
                }
                return .unavailable(status == 429 ? .rateLimited : .networkError)
            }
            // A 200 that parses to nothing means the account has no rate-limited window —
            // pay-as-you-go, for instance — rather than a failure.
            guard let snapshot = ClaudeUsageParser.parse(data: data) else {
                return .unavailable(.noLimits)
            }
            return .success(snapshot)
        } catch {
            Log.hooks.debug("Claude usage: request failed: \(error.localizedDescription)")
            return .unavailable(.networkError)
        }
    }
}

/// Outcome of one usage fetch: either a snapshot, or the reason there is none.
public enum ClaudeUsageFetch: Sendable, Equatable {
    case success(ClaudeUsageSnapshot)
    case unavailable(UsageUnavailableReason)
}
