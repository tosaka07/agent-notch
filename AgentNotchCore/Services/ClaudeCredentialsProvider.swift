import Foundation

/// Caches Claude credentials for the lifetime of the process so the credential source is read
/// as rarely as possible.
///
/// # Why
/// `UsageCoordinator` fetches usage every 180 seconds, which naively would mean reading the
/// Keychain or the credentials file every time. `ClaudeCredentialsStore` already avoids the
/// authorization dialog, but keeping access frequency low means that on any setup where a dialog
/// still appears, it appears at most once.
///
/// # Behavior
/// - Reads for real only on the first call; afterwards returns the in-memory cache until it expires.
/// - **Once a load fails, never retries for the rest of the process** (`hasGivenUp`), so a user who
///   dismissed the authorization dialog is not asked again. Call `reset()` explicitly to allow
///   retrying (e.g. when the setting is toggled back on).
/// - On a 401, `invalidate()` drops the cache so the next call reads again. That is deliberately
///   not treated as giving up, so token rotation is picked up.
public actor ClaudeCredentialsProvider {
    public static let shared = ClaudeCredentialsProvider()

    private let loader: @Sendable () -> ClaudeCredentials?
    private var cached: ClaudeCredentials?
    private var hasGivenUp = false

    public init(loader: @escaping @Sendable () -> ClaudeCredentials? = { ClaudeCredentialsStore.load() }) {
        self.loader = loader
    }

    /// What the credential source currently offers.
    ///
    /// `expired` is kept separate from `unavailable` because the two need different words in the
    /// UI and different handling here: an expired token is not worth spending a request on, but it
    /// also is not a dead end — Claude Code refreshes it roughly twice a day, so every poll should
    /// look again.
    public enum TokenState: Sendable, Equatable {
        case valid(String)
        case expired
        case unavailable
    }

    /// Resolves the current token state, reading the source only when the cache cannot answer.
    public func tokenState(now: Date = Date()) -> TokenState {
        if let cached, !cached.isExpired(now: now) {
            return .valid(cached.accessToken)
        }
        // Drop the expired cache; the reload below still goes through the give-up check.
        cached = nil

        guard !hasGivenUp else { return .unavailable }

        guard let loaded = loader() else {
            hasGivenUp = true
            Log.hooks.debug("Claude credentials: unavailable, not retrying for the rest of this process")
            return .unavailable
        }

        // A freshly loaded token that is *already* expired means Claude Code has not run for
        // longer than the token's lifetime. Agent Notch cannot refresh it, so handing it out
        // would buy a guaranteed 401 every poll. It is deliberately left uncached, so the next
        // poll re-reads the source and picks up Claude Code's refresh as soon as it happens.
        guard !loaded.isExpired(now: now) else {
            Log.hooks.debug("Claude credentials: token expired; waiting for Claude Code to refresh it")
            return .expired
        }

        cached = loaded
        return .valid(loaded.accessToken)
    }

    /// Returns a valid access token, or `nil` if none can be obtained.
    public func accessToken(now: Date = Date()) -> String? {
        guard case .valid(let token) = tokenState(now: now) else { return nil }
        return token
    }

    /// Call this on a 401. Only the cache is discarded; the next call reads again.
    public func invalidate() {
        cached = nil
    }

    /// Clears the given-up state and allows retrying (e.g. when usage display is switched on in settings).
    public func reset() {
        cached = nil
        hasGivenUp = false
    }

    /// For tests and diagnostics.
    public var isGivenUp: Bool { hasGivenUp }
}
