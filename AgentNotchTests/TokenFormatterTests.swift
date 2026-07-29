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

/// The formatter's output is localized, so asserting on literal text would only
/// pass under one system locale. Instead we check the numeric part and that each
/// unit keeps a distinct suffix.
@Suite("RelativeTimeFormatter Tests")
struct RelativeTimeFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    /// Everything except the digits — the localized unit and "ago" wording.
    private func unitSuffix(_ text: String) -> String {
        text.filter { !$0.isNumber }
    }

    private func format(secondsAgo: TimeInterval) -> String {
        RelativeTimeFormatter.format(since: now.addingTimeInterval(-secondsAgo), relativeTo: now)
    }

    @Test("Seconds carry the elapsed second count")
    func seconds() {
        #expect(format(secondsAgo: 42).contains("42"))
    }

    @Test("Minutes carry the elapsed minute count")
    func minutes() {
        #expect(format(secondsAgo: 5 * 60).contains("5"))
    }

    @Test("Days carry the elapsed day count")
    func days() {
        #expect(format(secondsAgo: 3 * 24 * 60 * 60).contains("3"))
    }

    @Test("Months carry the elapsed month count")
    func months() {
        let date = calendar.date(byAdding: .month, value: -2, to: now)!
        #expect(RelativeTimeFormatter.format(since: date, relativeTo: now).contains("2"))
    }

    @Test("Each unit renders a distinct suffix")
    func unitsAreDistinct() {
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let suffixes = [
            unitSuffix(format(secondsAgo: 42)),
            unitSuffix(format(secondsAgo: 5 * 60)),
            unitSuffix(format(secondsAgo: 2 * 60 * 60)),
            unitSuffix(format(secondsAgo: 3 * 24 * 60 * 60)),
            unitSuffix(RelativeTimeFormatter.format(since: twoMonthsAgo, relativeTo: now)),
        ]
        #expect(Set(suffixes).count == suffixes.count)
    }
}
