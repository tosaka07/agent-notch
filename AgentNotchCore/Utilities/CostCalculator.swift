import Foundation

/// Estimates cost from token counts.
///
/// # Important: this is a "what it would cost at API rates" estimate
/// On a Max or Pro subscription the actual bill is a flat fee, so these amounts are not what is
/// charged. The UI must always label them as API-rate estimates.
///
/// # Price table
/// Hardcoded, since the app is meant to work offline. Keys are the model names as they actually
/// appear in Claude Code / Codex transcripts (`claude-sonnet-5`, `gpt-5.3-codex`, ...).
/// **Each model holds an array of "effective from" tiers so price changes can be represented**
/// (e.g. Sonnet 5's introductory pricing ends 2026-09-01, going $2 to $3 / $10 to $15).
///
/// # Cache price multipliers (relative to input)
/// - 5-minute cache write: 1.25x
/// - **1-hour cache write: 2x**. About half of real cache writes are 1h, so a flat 1.25x would
///   understate cost substantially.
/// - cache read: 0.1x
///
/// Sources:
/// - https://platform.claude.com/docs/en/about-claude/pricing
/// - https://developers.openai.com/api/docs/pricing
public enum CostCalculator {
    /// Price in USD per 1M tokens.
    public struct ModelPricing: Sendable, Equatable {
        public let inputPerMillion: Double
        public let outputPerMillion: Double
        /// Cache-write price for the 5-minute TTL.
        public let cacheWrite5mPerMillion: Double
        /// Cache-write price for the 1-hour TTL.
        public let cacheWrite1hPerMillion: Double
        public let cacheReadPerMillion: Double

        public init(
            inputPerMillion: Double,
            outputPerMillion: Double,
            cacheWrite5mPerMillion: Double,
            cacheWrite1hPerMillion: Double,
            cacheReadPerMillion: Double
        ) {
            self.inputPerMillion = inputPerMillion
            self.outputPerMillion = outputPerMillion
            self.cacheWrite5mPerMillion = cacheWrite5mPerMillion
            self.cacheWrite1hPerMillion = cacheWrite1hPerMillion
            self.cacheReadPerMillion = cacheReadPerMillion
        }

        /// Builds the cache prices from the input price using the standard multipliers (5m 1.25x, 1h 2x, read 0.1x).
        public static func standard(input: Double, output: Double) -> ModelPricing {
            ModelPricing(
                inputPerMillion: input,
                outputPerMillion: output,
                cacheWrite5mPerMillion: input * 1.25,
                cacheWrite1hPerMillion: input * 2,
                cacheReadPerMillion: input * 0.1
            )
        }
    }

    /// A price effective from some point in time. A nil `effectiveFrom` means "effective from the start".
    struct PricingTier: Sendable {
        let effectiveFrom: Date?
        let pricing: ModelPricing
    }

    private static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: iso) ?? .distantPast
    }

    /// Model name to its prices over time.
    ///
    /// On the Codex (OpenAI) side the official pricing page lists only `gpt-5.3-codex` and later,
    /// so prices for the older codex models (`gpt-5-codex`, `gpt-5.1-codex`, `gpt-5.2-codex`, ...)
    /// and for `codex-auto-review` are **unavailable**. Guessed values would present a wrong amount
    /// as fact, so they are deliberately left out and surface in `unsupportedModels` instead.
    static let pricingTiers: [String: [PricingTier]] = [
        // MARK: Claude
        "claude-fable-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 10, output: 50))],
        "claude-opus-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-8": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-7": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-6": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        // Sonnet 5's introductory pricing ends 2026-09-01.
        "claude-sonnet-5": [
            PricingTier(effectiveFrom: nil, pricing: .standard(input: 2, output: 10)),
            PricingTier(effectiveFrom: date("2026-09-01"), pricing: .standard(input: 3, output: 15)),
        ],
        "claude-sonnet-4-6": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 3, output: 15))],
        "claude-sonnet-4-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 3, output: 15))],
        "claude-haiku-4-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 1, output: 5))],
        "claude-opus-4-1": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 15, output: 75))],

        // MARK: OpenAI / Codex (only those with published prices)
        "gpt-5.6-sol": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 30))],
        "gpt-5.6-terra": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 2.5, output: 15))],
        "gpt-5.6-luna": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 1, output: 6))],
        "gpt-5.5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 30))],
        "gpt-5.5-pro": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 30, output: 180))],
        "gpt-5.4": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 2.5, output: 15))],
        "gpt-5.4-mini": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 0.75, output: 4.5))],
        "gpt-5.4-nano": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 0.2, output: 1.25))],
        "gpt-5.3-codex": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 1.75, output: 14))],
    ]

    private static func pricing(from tiers: [PricingTier], at date: Date) -> ModelPricing? {
        // Take the newest tier whose effectiveFrom is at or before `date`.
        let applicable =
            tiers
            .filter { ($0.effectiveFrom ?? .distantPast) <= date }
            .max { ($0.effectiveFrom ?? .distantPast) < ($1.effectiveFrom ?? .distantPast) }
        return applicable?.pricing ?? tiers.first(where: { $0.effectiveFrom == nil })?.pricing
    }

    /// Normalizes a model name to a key in the price table.
    /// Transcripts also carry date-suffixed names such as `claude-haiku-4-5-20251001`.
    static func normalize(model: String) -> String {
        let lower = model.lowercased()
        if let match = pricingTiers.keys.first(where: { lower == $0 }) { return match }
        // Take the longest prefix match (`claude-haiku-4-5-20251001` matches `claude-haiku-4-5`).
        return pricingTiers.keys
            .filter { lower.hasPrefix($0) }
            .max(by: { $0.count < $1.count }) ?? lower
    }

    /// Price for a model at a point in time. nil for unsupported models.
    public static func pricing(for model: String, at date: Date = .now) -> ModelPricing? {
        guard let tiers = pricingTiers[normalize(model: model)] else { return nil }
        return pricing(from: tiers, at: date)
    }

    /// Estimates cost from a token breakdown. Returns nil for unsupported models: returning 0
    /// would make "free" indistinguishable from "price unknown" and silently understate the total.
    public static func estimateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWrite5mTokens: Int = 0,
        cacheWrite1hTokens: Int = 0,
        cacheReadTokens: Int = 0,
        at date: Date = .now
    ) -> Double? {
        guard let pricing = pricing(for: model, at: date) else { return nil }
        let million = 1_000_000.0
        return Double(inputTokens) * pricing.inputPerMillion / million
            + Double(outputTokens) * pricing.outputPerMillion / million
            + Double(cacheWrite5mTokens) * pricing.cacheWrite5mPerMillion / million
            + Double(cacheWrite1hTokens) * pricing.cacheWrite1hPerMillion / million
            + Double(cacheReadTokens) * pricing.cacheReadPerMillion / million
    }

    /// Fallback for when the 5m/1h cache split is unavailable; counts everything as 5m.
    public static func estimateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int
    ) -> Double {
        estimateCost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWrite5mTokens: cachedTokens
        ) ?? 0
    }

    /// Display format for an amount.
    ///
    /// Grouping separators are left to the standard `FormatStyle.currency`; a hand-rolled
    /// `String(format:)` would not insert commas. **The locale is pinned to en_US** because the
    /// price table is in USD, and otherwise the runtime locale could render it as "US$" or change
    /// how the decimals are handled.
    ///
    /// From three digits up, the decimals are dropped to save room in the narrow notch.
    public static func formatCost(_ cost: Double) -> String {
        if cost > 0, cost < 0.01 { return "<$0.01" }
        return cost.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(cost >= 100 ? 0 : 2))
                .locale(Locale(identifier: "en_US"))
        )
    }
}
