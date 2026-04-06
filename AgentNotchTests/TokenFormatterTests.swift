import Foundation
import Testing
@testable import AgentNotchCore

@Suite("TokenFormatter Tests")
struct TokenFormatterTests {
    @Test("Zero returns '0'")
    func zero() {
        #expect(TokenFormatter.format(0) == "0")
    }

    @Test("Small number returns as-is")
    func small() {
        #expect(TokenFormatter.format(42) == "42")
        #expect(TokenFormatter.format(999) == "999")
    }

    @Test("Thousands formatted with k suffix")
    func thousands() {
        #expect(TokenFormatter.format(12_400) == "12.4k")
        #expect(TokenFormatter.format(1_000) == "1.0k")
        #expect(TokenFormatter.format(999_999) == "1000.0k")
    }

    @Test("Millions formatted with M suffix")
    func millions() {
        #expect(TokenFormatter.format(1_500_000) == "1.5M")
        #expect(TokenFormatter.format(1_000_000) == "1.0M")
    }
}

@Suite("RelativeTimeFormatter Tests")
struct RelativeTimeFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Seconds formatted as seconds ago")
    func seconds() {
        let date = now.addingTimeInterval(-42)
        #expect(RelativeTimeFormatter.format(since: date, relativeTo: now) == "42秒前")
    }

    @Test("Minutes formatted as minutes ago")
    func minutes() {
        let date = now.addingTimeInterval(-(5 * 60))
        #expect(RelativeTimeFormatter.format(since: date, relativeTo: now) == "5分前")
    }

    @Test("Days formatted as days ago")
    func days() {
        let date = now.addingTimeInterval(-(3 * 24 * 60 * 60))
        #expect(RelativeTimeFormatter.format(since: date, relativeTo: now) == "3日前")
    }

    @Test("Months formatted as months ago")
    func months() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .month, value: -2, to: now)!
        #expect(RelativeTimeFormatter.format(since: date, relativeTo: now) == "2ヵ月前")
    }
}
