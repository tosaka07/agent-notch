import Foundation
import Testing

@testable import AgentNotchCore

@Suite("ClaudeCredentialsStore のパース")
struct ClaudeCredentialsStoreTests {
    @Test("claudeAiOauth 配下の accessToken と expiresAt(ミリ秒) を読む")
    func parsesNestedOauthPayload() throws {
        let json = """
        {"claudeAiOauth": {"accessToken": "sk-ant-oat01-dummy", "expiresAt": 1780000000000}}
        """
        let creds = try #require(ClaudeCredentialsStore.parse(data: Data(json.utf8)))
        #expect(creds.accessToken == "sk-ant-oat01-dummy")
        #expect(creds.expiresAt == Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test("トップレベルの accessToken にもフォールバックする")
    func parsesFlatPayload() throws {
        let creds = try #require(ClaudeCredentialsStore.parse(data: Data(#"{"accessToken":"flat"}"#.utf8)))
        #expect(creds.accessToken == "flat")
        #expect(creds.expiresAt == nil)
    }

    @Test("空トークン・壊れた JSON は nil")
    func rejectsInvalidPayloads() {
        #expect(ClaudeCredentialsStore.parse(data: Data(#"{"accessToken":""}"#.utf8)) == nil)
        #expect(ClaudeCredentialsStore.parse(data: Data("not json".utf8)) == nil)
        #expect(ClaudeCredentialsStore.parse(data: Data(#"{"other":1}"#.utf8)) == nil)
    }

    @Test("expiresAt はミリ秒・秒・文字列いずれも扱える")
    func normalizesExpiry() {
        #expect(ClaudeCredentialsStore.expiry(from: 1_780_000_000_000) == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(ClaudeCredentialsStore.expiry(from: 1_780_000_000) == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(ClaudeCredentialsStore.expiry(from: "1780000000000") == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(ClaudeCredentialsStore.expiry(from: nil) == nil)
        #expect(ClaudeCredentialsStore.expiry(from: 0) == nil)
    }

    @Test("期限は leeway 込みで判定し、期限不明なら期限切れにしない")
    func expiryCheckUsesLeeway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(30))
        #expect(soon.isExpired(now: now, leeway: 60))

        let later = ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(600))
        #expect(!later.isExpired(now: now, leeway: 60))

        #expect(!ClaudeCredentials(accessToken: "t").isExpired(now: now))
    }
}

@Suite("ClaudeCredentialsProvider のキャッシュと諦め")
struct ClaudeCredentialsProviderTests {
    /// 呼び出し回数を数えるだけの loader。
    private final class Counter: @unchecked Sendable {
        var calls = 0
        var result: ClaudeCredentials?
        init(result: ClaudeCredentials?) { self.result = result }
    }

    private func makeProvider(_ counter: Counter) -> ClaudeCredentialsProvider {
        ClaudeCredentialsProvider { counter.calls += 1; return counter.result }
    }

    @Test("有効なトークンは 1 回だけ読み込み、以降はキャッシュを返す")
    func cachesToken() async {
        let counter = Counter(result: ClaudeCredentials(accessToken: "cached"))
        let provider = makeProvider(counter)

        for _ in 0..<5 {
            #expect(await provider.accessToken() == "cached")
        }
        #expect(counter.calls == 1)
    }

    @Test("取得失敗後はプロセス内で再試行しない")
    func givesUpAfterFailure() async {
        let counter = Counter(result: nil)
        let provider = makeProvider(counter)

        #expect(await provider.accessToken() == nil)
        #expect(await provider.accessToken() == nil)
        #expect(await provider.accessToken() == nil)
        #expect(counter.calls == 1)
        #expect(await provider.isGivenUp)
    }

    @Test("reset() で再試行を許可する")
    func resetAllowsRetry() async {
        let counter = Counter(result: nil)
        let provider = makeProvider(counter)

        #expect(await provider.accessToken() == nil)
        counter.result = ClaudeCredentials(accessToken: "recovered")
        await provider.reset()

        #expect(await provider.accessToken() == "recovered")
        #expect(counter.calls == 2)
    }

    @Test("invalidate() は諦めずに読み直す（401 でのローテーション追従）")
    func invalidateReloads() async {
        let counter = Counter(result: ClaudeCredentials(accessToken: "old"))
        let provider = makeProvider(counter)

        #expect(await provider.accessToken() == "old")
        counter.result = ClaudeCredentials(accessToken: "new")
        await provider.invalidate()

        #expect(await provider.accessToken() == "new")
        #expect(counter.calls == 2)
    }

    @Test("期限切れキャッシュは自動で読み直す")
    func reloadsExpiredToken() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let counter = Counter(result: ClaudeCredentials(accessToken: "expiring", expiresAt: now.addingTimeInterval(10)))
        let provider = makeProvider(counter)

        #expect(await provider.accessToken(now: now.addingTimeInterval(-3600)) == "expiring")
        counter.result = ClaudeCredentials(accessToken: "fresh", expiresAt: now.addingTimeInterval(86400))
        #expect(await provider.accessToken(now: now) == "fresh")
        #expect(counter.calls == 2)
    }
}
