import Foundation
import Testing
@testable import AgentNotch

@Suite("CostCalculator Tests")
struct CostCalculatorTests {
    @Test("Opus cost calculation is correct")
    func opusCost() {
        let cost = CostCalculator.estimateCost(
            model: "claude-opus-4-6",
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            cachedTokens: 500_000
        )
        // input: 1M * 15/1M = 15.0
        // output: 100k * 75/1M = 7.5
        // cached: 500k * 1.5/1M = 0.75
        // total = 23.25
        #expect(abs(cost - 23.25) < 0.001)
    }

    @Test("Unknown model returns zero cost")
    func unknownModel() {
        let cost = CostCalculator.estimateCost(
            model: "unknown-model",
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            cachedTokens: 0
        )
        #expect(cost == 0)
    }

    @Test("formatCost formats correctly")
    func formatCost() {
        #expect(CostCalculator.formatCost(0) == "$0.00")
        #expect(CostCalculator.formatCost(0.005) == "<$0.01")
        #expect(CostCalculator.formatCost(1.234) == "$1.23")
        #expect(CostCalculator.formatCost(15.5) == "$15.50")
    }
}
