import Foundation
import Testing

@testable import AgentNotchCore

/// SocketServer のハイジャック対策（#24）と TTL クリーンアップ（#25）を、
/// NWConnection に依存しない純粋なロジック単位でテストする。
struct SocketServerTests {

    // MARK: - #24 衝突検知（先勝ち）

    @Test("setIfAbsent: 未登録キーは挿入され true を返す")
    func setIfAbsentInsertsNewKey() {
        let dict = LockedDict<String, Int>()
        let inserted = dict.setIfAbsent("a", 1)
        #expect(inserted == true)
        #expect(dict.all().first?.1 == 1)
    }

    @Test("setIfAbsent: 既存キーへの登録は拒否され、既存値が保持される（先勝ち）")
    func setIfAbsentRejectsCollision() {
        let dict = LockedDict<String, Int>()
        #expect(dict.setIfAbsent("a", 1) == true)
        // 同じキーへの2回目の登録（攻撃者側の偽エントリを想定）は拒否される。
        let insertedAgain = dict.setIfAbsent("a", 999)
        #expect(insertedAgain == false)

        let all = dict.all()
        #expect(all.count == 1)
        #expect(all.first?.1 == 1)  // 既存エントリ（先に登録された正規セッション）が保持されている
    }

    @Test("setIfAbsent: remove 後は同じキーに再登録できる")
    func setIfAbsentAllowsReinsertAfterRemove() {
        let dict = LockedDict<String, Int>()
        #expect(dict.setIfAbsent("a", 1) == true)
        #expect(dict.remove("a") == 1)
        #expect(dict.setIfAbsent("a", 2) == true)
        #expect(dict.all().first?.1 == 2)
    }

    // MARK: - #25 TTL クリーンアップ

    @Test("removeAll(where:): 条件を満たすエントリのみ削除され、削除された値が返る")
    func removeAllWhereRemovesMatchingEntriesOnly() {
        let dict = LockedDict<String, Int>()
        dict.set("keep", 1)
        dict.set("drop1", 2)
        dict.set("drop2", 3)

        let removed = dict.removeAll { $0 >= 2 }

        #expect(Set(removed) == Set([2, 3]))
        let remaining = dict.all()
        #expect(remaining.count == 1)
        #expect(remaining.first?.0 == "keep")
    }

    @Test("isExpired: TTL 未満なら false")
    func isExpiredFalseWithinTTL() {
        let now = Date()
        let receivedAt = now.addingTimeInterval(-10)  // 10秒前
        #expect(SocketServer.isExpired(receivedAt: receivedAt, now: now, ttl: 130) == false)
    }

    @Test("isExpired: TTL ちょうどで true（境界値）")
    func isExpiredTrueAtExactBoundary() {
        let now = Date()
        let receivedAt = now.addingTimeInterval(-130)
        #expect(SocketServer.isExpired(receivedAt: receivedAt, now: now, ttl: 130) == true)
    }

    @Test("isExpired: TTL 超過なら true")
    func isExpiredTrueBeyondTTL() {
        let now = Date()
        let receivedAt = now.addingTimeInterval(-200)  // 130s を大きく超過
        #expect(SocketServer.isExpired(receivedAt: receivedAt, now: now, ttl: 130) == true)
    }

    @Test("デフォルト TTL は HookHandler.recvTimeoutSeconds（120s）にマージンを足した値以上")
    func defaultTTLCoversHookHandlerRecvTimeout() {
        // HookHandler 側の recv タイムアウト（120s）より短いと、
        // 応答がまだ間に合うはずのエントリを先に破棄してしまう。
        #expect(SocketServer.pendingTTLSeconds >= 120)
    }
}
