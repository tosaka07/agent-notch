import Foundation
import Testing

@testable import AgentNotchCore

@Suite("CostCalculator Tests")
struct CostCalculatorTests {
    /// Opus models bill input $5 / output $25 (the old $15/$75 table was a previous generation).
    @Test("Opus cost calculation is correct")
    func opusCost() throws {
        let cost = try #require(
            CostCalculator.estimateCost(
                model: "claude-opus-5",
                inputTokens: 1_000_000,
                outputTokens: 100_000,
                cacheWrite5mTokens: 500_000
            )
        )
        // input: 1M * 5/1M = 5.0
        // output: 100k * 25/1M = 2.5
        // cache write 5m: 500k * 6.25/1M = 3.125
        #expect(abs(cost - 10.625) < 0.001)
    }

    /// Cache pricing: 5m write 1.25x, 1h write 2x, read 0.1x. Regression test: write
    /// and read once shared a rate, which overestimated reads by 12.5x.
    ///
    /// The multipliers are what is under test, so this reads a model with a single price tier.
    /// Asking a dated model for "now" made the case expire on its own: it held Sonnet 5's
    /// introductory rate, which ended 2026-09-01 and took the suite red with it.
    @Test("Cache write and read are priced differently")
    func cachePricing() throws {
        let pricing = try #require(CostCalculator.pricing(for: "claude-opus-5"))
        #expect(abs(pricing.inputPerMillion - 5) < 0.001)
        #expect(abs(pricing.cacheWrite5mPerMillion - 6.25) < 0.001)
        #expect(abs(pricing.cacheWrite1hPerMillion - 10) < 0.001)
        #expect(abs(pricing.cacheReadPerMillion - 0.5) < 0.001)
    }

    /// Sonnet 5's introductory pricing ends on 2026-09-01, after which rates rise.
    @Test("Pricing tiers switch on their effective date")
    func datedPricingTiers() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let beforeIncrease = try #require(formatter.date(from: "2026-08-31"))
        let afterIncrease = try #require(formatter.date(from: "2026-09-02"))

        let introductory = try #require(CostCalculator.pricing(for: "claude-sonnet-5", at: beforeIncrease))
        let standard = try #require(CostCalculator.pricing(for: "claude-sonnet-5", at: afterIncrease))

        #expect(abs(introductory.outputPerMillion - 10) < 0.001)
        #expect(abs(standard.outputPerMillion - 15) < 0.001)
    }

    /// Model names with a date suffix must still resolve in the rate table.
    @Test("Model names with a date suffix normalize to the pricing table key")
    func normalizesDatedModelName() throws {
        let pricing = try #require(CostCalculator.pricing(for: "claude-haiku-4-5-20251001"))
        #expect(abs(pricing.outputPerMillion - 5) < 0.001)
    }

    /// An unknown rate returns nil: returning 0 would be indistinguishable from free
    /// and would silently underestimate cost.
    @Test("Unknown model returns nil so callers can flag it")
    func unknownModelReturnsNil() {
        #expect(
            CostCalculator.estimateCost(
                model: "unknown-model",
                inputTokens: 1_000_000,
                outputTokens: 100_000
            ) == nil
        )
        #expect(CostCalculator.pricing(for: "unknown-model") == nil)
    }

    @Test("formatCost formats correctly")
    func formatCost() {
        #expect(CostCalculator.formatCost(0) == "$0.00")
        #expect(CostCalculator.formatCost(0.005) == "<$0.01")
        #expect(CostCalculator.formatCost(1.234) == "$1.23")
        #expect(CostCalculator.formatCost(15.5) == "$15.50")
        // Three digits or more drop the decimals to save width (the notch is narrow).
        #expect(CostCalculator.formatCost(2511.52) == "$2,512")
        // Grouping separators are left to the standard currency FormatStyle. The locale
        // is pinned to en_US, so the output does not depend on the host's region setting.
        // Exactly .5 rounds to even (the FormatStyle default, matching printf).
        #expect(CostCalculator.formatCost(1234.5) == "$1,234")
        #expect(CostCalculator.formatCost(1235.7) == "$1,236")
        #expect(CostCalculator.formatCost(99.999) == "$100.00")
    }
}
