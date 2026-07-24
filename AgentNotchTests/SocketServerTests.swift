import Foundation
import Testing

@testable import AgentNotchCore

/// SocketServer のハイジャック対策（#24）を、NWConnection に依存しない
/// 純粋なロジック単位（LockedDict.setIfAbsent）でテストする。
struct SocketServerTests {

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
}
