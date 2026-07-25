import Foundation

/// 1 日分のコスト・トークン集計（agent 非依存）。
public struct DailyCost: Sendable, Equatable, Identifiable {
    /// その日の 00:00（ローカルタイムゾーン）。
    public let day: Date
    /// API 換算の推定コスト（USD）。サブスクリプションでは実際の請求額ではない。
    public let estimatedCostUSD: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheWriteTokens: Int
    public let cacheReadTokens: Int

    public var id: Date { day }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    public init(
        day: Date,
        estimatedCostUSD: Double,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) {
        self.day = day
        self.estimatedCostUSD = estimatedCostUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

/// 日毎コストの集計結果。
public struct DailyCostReport: Sendable, Equatable {
    /// 日付昇順。データが無い日は含まれない（チャート側で 0 埋めする）。
    public let days: [DailyCost]
    /// 単価が判明せずコストに算入できなかったモデル名（UI で注記するため）。
    public let unsupportedModels: [String]
    public let computedAt: Date

    public var totalCostUSD: Double { days.reduce(0) { $0 + $1.estimatedCostUSD } }

    public init(days: [DailyCost], unsupportedModels: [String], computedAt: Date) {
        self.days = days
        self.unsupportedModels = unsupportedModels
        self.computedAt = computedAt
    }

    public static let empty = DailyCostReport(days: [], unsupportedModels: [], computedAt: .distantPast)

    /// 直近 `count` 日を、データが無い日も 0 で埋めた連続配列で返す（bar chart 用）。
    /// 日付が飛んでいる実データをそのまま並べると横軸が歪むため。
    public func recentDaysFilled(count: Int, now: Date = .now, calendar: Calendar = .current) -> [DailyCost] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.day), $0) })
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDay[day] ?? DailyCost(day: day, estimatedCostUSD: 0)
        }
    }
}
