import Foundation

/// Cost and token totals for a single day (agent-agnostic).
public struct DailyCost: Sendable, Equatable, Identifiable {
    /// Midnight of that day in the local time zone.
    public let day: Date
    /// Estimated cost in USD at API rates. On a subscription plan this is not the amount billed.
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

/// Aggregated per-day cost report.
public struct DailyCostReport: Sendable, Equatable {
    /// Ascending by date. Days without data are omitted; the chart fills them with zeros.
    public let days: [DailyCost]
    /// Models with no known pricing, so their usage is excluded from the cost. Surfaced as a note in the UI.
    public let unsupportedModels: [String]
    public let computedAt: Date

    public var totalCostUSD: Double { days.reduce(0) { $0 + $1.estimatedCostUSD } }

    public init(days: [DailyCost], unsupportedModels: [String], computedAt: Date) {
        self.days = days
        self.unsupportedModels = unsupportedModels
        self.computedAt = computedAt
    }

    public static let empty = DailyCostReport(days: [], unsupportedModels: [], computedAt: .distantPast)

    /// Returns the last `count` days as a contiguous array, filling missing days with zero (for the bar chart).
    /// Plotting the raw data with gaps would distort the horizontal axis.
    public func recentDaysFilled(count: Int, now: Date = .now, calendar: Calendar = .current) -> [DailyCost] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.day), $0) })
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDay[day] ?? DailyCost(day: day, estimatedCostUSD: 0)
        }
    }
}
