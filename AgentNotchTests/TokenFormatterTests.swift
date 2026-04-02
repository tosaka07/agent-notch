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
