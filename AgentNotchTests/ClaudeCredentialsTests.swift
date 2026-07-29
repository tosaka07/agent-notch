import Foundation
import Testing

@testable import AgentNotchCore

@Suite("ClaudeCredentialsStore Parsing")
struct ClaudeCredentialsStoreTests {
    @Test("Reads accessToken and expiresAt (milliseconds) under claudeAiOauth")
    func parsesNestedOauthPayload() throws {
        let json = """
            {"claudeAiOauth": {"accessToken": "sk-ant-oat01-dummy", "expiresAt": 1780000000000}}
            """
        let creds = try #require(ClaudeCredentialsStore.parse(data: Data(json.utf8)))
        #expect(creds.accessToken == "sk-ant-oat01-dummy")
        #expect(creds.expiresAt == Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test("Falls back to a top-level accessToken")
    func parsesFlatPayload() throws {
        let creds = try #require(ClaudeCredentialsStore.parse(data: Data(#"{"accessToken":"flat"}"#.utf8)))
        #expect(creds.accessToken == "flat")
        #expect(creds.expiresAt == nil)
    }

    @Test("Empty token or malformed JSON yields nil")
    func rejectsInvalidPayloads() {
        #expect(ClaudeCredentialsStore.parse(data: Data(#"{"accessToken":""}"#.utf8)) == nil)
        #expect(ClaudeCredentialsStore.parse(data: Data("not json".utf8)) == nil)
        #expect(ClaudeCredentialsStore.parse(data: Data(#"{"other":1}"#.utf8)) == nil)
    }

    @Test("expiresAt accepts milliseconds, seconds, or a string")
    func normalizesExpiry() {
        #expect(
            ClaudeCredentialsStore.expiry(from: 1_780_000_000_000)
                == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(
            ClaudeCredentialsStore.expiry(from: 1_780_000_000) == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(
            ClaudeCredentialsStore.expiry(from: "1780000000000") == Date(timeIntervalSince1970: 1_780_000_000)
        )
        #expect(ClaudeCredentialsStore.expiry(from: nil) == nil)
        #expect(ClaudeCredentialsStore.expiry(from: 0) == nil)
    }

    @Test("Expiry check honors leeway; unknown expiry is never treated as expired")
    func expiryCheckUsesLeeway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(30))
        #expect(soon.isExpired(now: now, leeway: 60))

        let later = ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(600))
        #expect(!later.isExpired(now: now, leeway: 60))

        #expect(!ClaudeCredentials(accessToken: "t").isExpired(now: now))
    }
}

@Suite("ClaudeCredentialsProvider Caching and Give-up")
struct ClaudeCredentialsProviderTests {
    /// A loader that only counts how many times it was called.
    private final class Counter: @unchecked Sendable {
        var calls = 0
        var result: ClaudeCredentials?
        init(result: ClaudeCredentials?) { self.result = result }
    }

    private func makeProvider(_ counter: Counter) -> ClaudeCredentialsProvider {
        ClaudeCredentialsProvider {
            counter.calls += 1
            return counter.result
        }
    }

    @Test("A valid token is loaded once and served from cache afterwards")
    func cachesToken() async {
        let counter = Counter(result: ClaudeCredentials(accessToken: "cached"))
        let provider = makeProvider(counter)

        for _ in 0..<5 {
            #expect(await provider.accessToken() == "cached")
        }
        #expect(counter.calls == 1)
    }

    @Test("Does not retry within the process after a load failure")
    func givesUpAfterFailure() async {
        let counter = Counter(result: nil)
        let provider = makeProvider(counter)

        #expect(await provider.accessToken() == nil)
        #expect(await provider.accessToken() == nil)
        #expect(await provider.accessToken() == nil)
        #expect(counter.calls == 1)
        #expect(await provider.isGivenUp)
    }

    @Test("reset() re-enables retrying")
    func resetAllowsRetry() async {
        let counter = Counter(result: nil)
        let provider = makeProvider(counter)

        #expect(await provider.accessToken() == nil)
        counter.result = ClaudeCredentials(accessToken: "recovered")
        await provider.reset()

        #expect(await provider.accessToken() == "recovered")
        #expect(counter.calls == 2)
    }

    @Test("invalidate() reloads instead of giving up (follows rotation on 401)")
    func invalidateReloads() async {
        let counter = Counter(result: ClaudeCredentials(accessToken: "old"))
        let provider = makeProvider(counter)

        #expect(await provider.accessToken() == "old")
        counter.result = ClaudeCredentials(accessToken: "new")
        await provider.invalidate()

        #expect(await provider.accessToken() == "new")
        #expect(counter.calls == 2)
    }

    @Test("An expired cache entry is reloaded automatically")
    func reloadsExpiredToken() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let counter = Counter(
            result: ClaudeCredentials(accessToken: "expiring", expiresAt: now.addingTimeInterval(10)))
        let provider = makeProvider(counter)

        #expect(await provider.accessToken(now: now.addingTimeInterval(-3600)) == "expiring")
        counter.result = ClaudeCredentials(accessToken: "fresh", expiresAt: now.addingTimeInterval(86400))
        #expect(await provider.accessToken(now: now) == "fresh")
        #expect(counter.calls == 2)
    }

    /// Regression: the source can only ever hold an expired token when Claude Code has not run
    /// for longer than the token's lifetime, because Claude Code is the only thing that refreshes
    /// it. Handing that token out bought a guaranteed 401 on every poll and, worse, presented as
    /// "usage display disappeared" rather than "the token needs refreshing".
    @Test("A freshly loaded token that is already expired is reported, not handed out")
    func reportsExpiredTokenInsteadOfServingIt() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let counter = Counter(
            result: ClaudeCredentials(accessToken: "stale", expiresAt: now.addingTimeInterval(-1))
        )
        let provider = makeProvider(counter)

        #expect(await provider.tokenState(now: now) == .expired)
        #expect(await provider.accessToken(now: now) == nil)
        // Expiry is not giving up: Claude Code refreshes a couple of times a day, so every call
        // must look again rather than latch off.
        #expect(await provider.isGivenUp == false)
    }

    @Test("An expired token is picked up again as soon as the source refreshes it")
    func recoversOnceClaudeCodeRefreshes() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let counter = Counter(
            result: ClaudeCredentials(accessToken: "stale", expiresAt: now.addingTimeInterval(-1))
        )
        let provider = makeProvider(counter)

        #expect(await provider.tokenState(now: now) == .expired)
        counter.result = ClaudeCredentials(accessToken: "refreshed", expiresAt: now.addingTimeInterval(28800))

        #expect(await provider.tokenState(now: now) == .valid("refreshed"))
    }

    @Test("A missing source is reported as unavailable, distinct from expired")
    func distinguishesMissingFromExpired() async {
        let counter = Counter(result: nil)
        let provider = makeProvider(counter)

        #expect(await provider.tokenState() == .unavailable)
    }
}
