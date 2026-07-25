import Foundation
import Testing
@testable import AgentNotchCore

@Suite("CostCalculator Tests")
struct CostCalculatorTests {
    /// Opus 系は input $5 / output $25（旧テーブルの $15/$75 は古い世代の値だった）。
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

    /// キャッシュは 5m write 1.25x / 1h write 2x / read 0.1x。
    /// 以前は write と read を同一単価にしていたため read が 12.5 倍高く見積もられていた。
    @Test("Cache write and read are priced differently")
    func cachePricing() throws {
        let pricing = try #require(CostCalculator.pricing(for: "claude-sonnet-5"))
        #expect(abs(pricing.inputPerMillion - 2) < 0.001)
        #expect(abs(pricing.cacheWrite5mPerMillion - 2.5) < 0.001)
        #expect(abs(pricing.cacheWrite1hPerMillion - 4) < 0.001)
        #expect(abs(pricing.cacheReadPerMillion - 0.2) < 0.001)
    }

    /// Sonnet 5 は 2026-09-01 に導入価格が終わって値上げされる。
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

    /// 日付サフィックス付きのモデル名も単価テーブルに解決する。
    @Test("Model names with a date suffix normalize to the pricing table key")
    func normalizesDatedModelName() throws {
        let pricing = try #require(CostCalculator.pricing(for: "claude-haiku-4-5-20251001"))
        #expect(abs(pricing.outputPerMillion - 5) < 0.001)
    }

    /// 単価不明を 0 で返すと「無料」と区別できず静かに過小評価するので nil を返す。
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
        // 3 桁以上は小数を落として桁を稼ぐ（notch の狭い幅で読めるように）。
        #expect(CostCalculator.formatCost(2511.52) == "$2,512")
        // 桁区切りは標準の currency FormatStyle 任せ。ロケールは en_US 固定なので
        // 実行環境の地域設定に依らず同じ表記になる。
        // ちょうど .5 は偶数側へ丸まる（FormatStyle の既定。printf と同じ挙動）。
        #expect(CostCalculator.formatCost(1234.5) == "$1,234")
        #expect(CostCalculator.formatCost(1235.7) == "$1,236")
        #expect(CostCalculator.formatCost(99.999) == "$100.00")
    }
}
