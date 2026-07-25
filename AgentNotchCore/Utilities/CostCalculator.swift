import Foundation

/// トークン数からコストを推定する。
///
/// # 重要な前提: これは「API 課金だったらいくらか」の換算推定値
/// Max / Pro などのサブスクリプションでは実際の請求は定額なので、ここで出る金額は
/// 請求額ではない。UI では必ず「API 換算推定」であることを示すこと。
///
/// # 単価テーブル
/// オフライン前提のアプリなのでハードコードする。モデル名は Claude Code / Codex の
/// transcript に現れる実際の値（`claude-sonnet-5`, `gpt-5.3-codex` 等）をキーにする。
/// **値上げ・値下げに対応するため、モデルごとに「いつから有効な単価か」の配列で持つ**
/// （例: Sonnet 5 は 2026-09-01 に導入価格が終わって $2→$3 / $10→$15 になる）。
///
/// # キャッシュの単価倍率（input 比）
/// - 5 分 cache write: 1.25x
/// - **1 時間 cache write: 2x**（実データでは cache write の約半分が 1h。一律 1.25x だと大幅な過小評価）
/// - cache read: 0.1x
///
/// 出典:
/// - https://platform.claude.com/docs/en/about-claude/pricing
/// - https://developers.openai.com/api/docs/pricing
public enum CostCalculator {
    /// 1M トークンあたりの単価（USD）。
    public struct ModelPricing: Sendable, Equatable {
        public let inputPerMillion: Double
        public let outputPerMillion: Double
        /// 5 分 TTL の cache write 単価。
        public let cacheWrite5mPerMillion: Double
        /// 1 時間 TTL の cache write 単価。
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

        /// input 単価から標準倍率（5m 1.25x / 1h 2x / read 0.1x）で組み立てる。
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

    /// ある時点から有効な単価。`effectiveFrom` が nil なら「最初から有効」。
    struct PricingTier: Sendable {
        let effectiveFrom: Date?
        let pricing: ModelPricing
    }

    private static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: iso) ?? .distantPast
    }

    /// モデル名 → 単価（時期別）。
    ///
    /// Codex（OpenAI）側は公式価格ページに `gpt-5.3-codex` 以降しか掲載が無く、
    /// 旧 codex 系（`gpt-5-codex` / `gpt-5.1-codex` / `gpt-5.2-codex` 等）と
    /// `codex-auto-review` の単価は**取得できない**。推測値を入れると誤った金額を
    /// 断定的に見せることになるので、あえて登録しない（`unsupportedModels` に載る）。
    static let pricingTiers: [String: [PricingTier]] = [
        // MARK: Claude
        "claude-fable-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 10, output: 50))],
        "claude-opus-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-8": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-7": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-6": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        "claude-opus-4-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 5, output: 25))],
        // Sonnet 5 は 2026-09-01 に導入価格が終了する。
        "claude-sonnet-5": [
            PricingTier(effectiveFrom: nil, pricing: .standard(input: 2, output: 10)),
            PricingTier(effectiveFrom: date("2026-09-01"), pricing: .standard(input: 3, output: 15)),
        ],
        "claude-sonnet-4-6": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 3, output: 15))],
        "claude-sonnet-4-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 3, output: 15))],
        "claude-haiku-4-5": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 1, output: 5))],
        "claude-opus-4-1": [PricingTier(effectiveFrom: nil, pricing: .standard(input: 15, output: 75))],

        // MARK: OpenAI / Codex（公式に掲載があるものだけ）
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

    /// 後方互換のための素の単価表（時期別を潰した現在の値）。
    public static var pricingTable: [String: ModelPricing] {
        pricingTiers.compactMapValues { pricing(from: $0, at: .now) }
    }

    private static func pricing(from tiers: [PricingTier], at date: Date) -> ModelPricing? {
        // effectiveFrom が date 以前のものの中で最も新しいものを採用する。
        let applicable = tiers
            .filter { ($0.effectiveFrom ?? .distantPast) <= date }
            .max { ($0.effectiveFrom ?? .distantPast) < ($1.effectiveFrom ?? .distantPast) }
        return applicable?.pricing ?? tiers.first(where: { $0.effectiveFrom == nil })?.pricing
    }

    /// モデル名を単価テーブルのキーに正規化する。
    /// transcript には `claude-haiku-4-5-20251001` のように日付サフィックス付きの名前も現れる。
    static func normalize(model: String) -> String {
        let lower = model.lowercased()
        if let match = pricingTiers.keys.first(where: { lower == $0 }) { return match }
        // 前方一致で最長のキーを採用（`claude-haiku-4-5-20251001` → `claude-haiku-4-5`）。
        return pricingTiers.keys
            .filter { lower.hasPrefix($0) }
            .max(by: { $0.count < $1.count }) ?? lower
    }

    /// 指定モデル・指定時点の単価。未対応モデルは nil。
    public static func pricing(for model: String, at date: Date = .now) -> ModelPricing? {
        guard let tiers = pricingTiers[normalize(model: model)] else { return nil }
        return pricing(from: tiers, at: date)
    }

    /// トークン内訳からコストを推定する。未対応モデルは nil を返す
    /// （0 を返すと「無料」と「単価不明」が区別できず、静かに過小評価されるため）。
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

    /// キャッシュの 5m/1h 区別が取れない場合のフォールバック（全量を 5m 扱い）。
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

    public static func formatCost(_ cost: Double) -> String {
        if cost == 0 {
            return "$0.00"
        } else if cost < 0.01 {
            return "<$0.01"
        } else if cost >= 100 {
            return String(format: "$%.0f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }
}
