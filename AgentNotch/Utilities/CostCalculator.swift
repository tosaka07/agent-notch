import Foundation

enum CostCalculator {
    struct ModelPricing: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cachedPerMillion: Double
    }

    static let pricingTable: [String: ModelPricing] = [
        "claude-opus-4-6": ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cachedPerMillion: 1.5),
        "claude-sonnet-4-6": ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cachedPerMillion: 0.3),
        "claude-haiku-4-5": ModelPricing(inputPerMillion: 0.8, outputPerMillion: 4, cachedPerMillion: 0.08),
        "o3": ModelPricing(inputPerMillion: 10, outputPerMillion: 40, cachedPerMillion: 2.5),
        "o4-mini": ModelPricing(inputPerMillion: 1.1, outputPerMillion: 4.4, cachedPerMillion: 0.275),
        "gpt-4.1": ModelPricing(inputPerMillion: 2, outputPerMillion: 8, cachedPerMillion: 0.5),
        "gemini-2.5-pro": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10, cachedPerMillion: 0.315),
        "gemini-2.5-flash": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.6, cachedPerMillion: 0.0375),
    ]

    static func estimateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int
    ) -> Double {
        guard let pricing = pricingTable[model] else { return 0 }
        let input = Double(inputTokens) * pricing.inputPerMillion / 1_000_000
        let output = Double(outputTokens) * pricing.outputPerMillion / 1_000_000
        let cached = Double(cachedTokens) * pricing.cachedPerMillion / 1_000_000
        return input + output + cached
    }

    static func formatCost(_ cost: Double) -> String {
        if cost == 0 {
            return "$0.00"
        } else if cost < 0.01 {
            return "<$0.01"
        } else {
            return String(format: "$%.2f", cost)
        }
    }
}
