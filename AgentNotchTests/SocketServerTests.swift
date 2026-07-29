import Foundation
import Testing

@testable import AgentNotchCore

/// Tests SocketServer's hijack protection and TTL cleanup as pure logic, without
/// depending on NWConnection.
struct SocketServerTests {

    // MARK: - Collision detection (first writer wins)

    @Test("setIfAbsent: an unused key is inserted and returns true")
    func setIfAbsentInsertsNewKey() {
        let dict = LockedDict<String, Int>()
        let inserted = dict.setIfAbsent("a", 1)
        #expect(inserted == true)
        #expect(dict.all().first?.1 == 1)
    }

    @Test("setIfAbsent: an existing key is rejected and keeps its value (first writer wins)")
    func setIfAbsentRejectsCollision() {
        let dict = LockedDict<String, Int>()
        #expect(dict.setIfAbsent("a", 1) == true)
        // A second registration for the same key (a spoofed entry) is rejected.
        let insertedAgain = dict.setIfAbsent("a", 999)
        #expect(insertedAgain == false)

        let all = dict.all()
        #expect(all.count == 1)
        #expect(all.first?.1 == 1)  // the original entry (the legitimate session) survives
    }

    @Test("setIfAbsent: the same key can be reused after remove")
    func setIfAbsentAllowsReinsertAfterRemove() {
        let dict = LockedDict<String, Int>()
        #expect(dict.setIfAbsent("a", 1) == true)
        #expect(dict.remove("a") == 1)
        #expect(dict.setIfAbsent("a", 2) == true)
        #expect(dict.all().first?.1 == 2)
    }

    // MARK: - TTL cleanup

    @Test("removeAll(where:) removes only matching entries and returns the removed values")
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

    @Test("isExpired: false below the TTL")
    func isExpiredFalseWithinTTL() {
        let now = Date()
        let receivedAt = now.addingTimeInterval(-10)  // 10 seconds ago
        #expect(SocketServer.isExpired(receivedAt: receivedAt, now: now, ttl: 130) == false)
    }

    @Test("isExpired: true exactly at the TTL (boundary)")
    func isExpiredTrueAtExactBoundary() {
        let now = Date()
        let receivedAt = now.addingTimeInterval(-130)
        #expect(SocketServer.isExpired(receivedAt: receivedAt, now: now, ttl: 130) == true)
    }

    @Test("isExpired: true past the TTL")
    func isExpiredTrueBeyondTTL() {
        let now = Date()
        let receivedAt = now.addingTimeInterval(-200)  // well past 130s
        #expect(SocketServer.isExpired(receivedAt: receivedAt, now: now, ttl: 130) == true)
    }

    @Test("The default TTL is at least HookHandler.recvTimeoutSeconds (120s) plus a margin")
    func defaultTTLCoversHookHandlerRecvTimeout() {
        // A TTL shorter than HookHandler's recv timeout (120s) would discard entries
        // whose response could still arrive in time.
        #expect(SocketServer.pendingTTLSeconds >= 120)
    }
}
