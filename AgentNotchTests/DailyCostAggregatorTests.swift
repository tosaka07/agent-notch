import Foundation
import Testing

@testable import AgentNotchCore

/// Tests daily cost aggregation: row deduplication, cache pricing, and Codex
/// cumulative deltas.
@Suite("DailyCostAggregator Tests")
struct DailyCostAggregatorTests {
    /// Helper that writes jsonl into a temporary directory and runs the aggregator.
    private func withTempDirectory(_ body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-cost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.path)
    }

    private func write(_ lines: [String], to directory: String, name: String = "session.jsonl") throws {
        let path = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    private func claudeLine(
        messageId: String,
        requestId: String,
        model: String = "claude-sonnet-5",
        timestamp: String = "2026-07-20T10:00:00.000Z",
        input: Int = 0,
        output: Int = 0,
        cacheWrite5m: Int = 0,
        cacheWrite1h: Int = 0,
        cacheRead: Int = 0
    ) -> String {
        """
        {"timestamp":"\(timestamp)","requestId":"\(requestId)","message":{"id":"\(messageId)",\
        "model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),\
        "cache_creation_input_tokens":\(cacheWrite5m + cacheWrite1h),\
        "cache_creation":{"ephemeral_5m_input_tokens":\(cacheWrite5m),\
        "ephemeral_1h_input_tokens":\(cacheWrite1h)},"cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    // MARK: - Claude

    /// When one assignment (message.id + requestId) is split across lines, the **last
    /// line** counts, not the placeholders emitted while streaming.
    @Test("Claude: duplicate rows sharing a message.id count only the last line")
    func claudeDeduplicatesKeepingLastEntry() throws {
        try withTempDirectory { dir in
            try write(
                [
                    // Three lines under one key (thinking / text / tool_use); output settles in stages.
                    claudeLine(messageId: "msg_1", requestId: "req_1", output: 6),
                    claudeLine(messageId: "msg_1", requestId: "req_1", output: 100),
                    claudeLine(messageId: "msg_1", requestId: "req_1", output: 1000),
                ],
                to: dir
            )
            let report = DailyCostAggregator.claudeReport(projectsDirectory: dir)

            #expect(report.days.count == 1)
            // Only the final 1000 counts, not the sum of all three lines (1106).
            #expect(report.days.first?.outputTokens == 1000)
            // Sonnet 5 output at $10/Mtok, so 1000 tokens = $0.01
            #expect(abs((report.days.first?.estimatedCostUSD ?? 0) - 0.01) < 0.0001)
        }
    }

    /// Subagent logs carry distinct message.ids, so they never duplicate — leaving
    /// them out would simply lose the cost.
    @Test("Claude: logs under subagents are included in the aggregate")
    func claudeIncludesSubagentLogs() throws {
        try withTempDirectory { dir in
            try write([claudeLine(messageId: "msg_main", requestId: "req_main", output: 500)], to: dir)
            try write(
                [claudeLine(messageId: "msg_sub", requestId: "req_sub", output: 700)],
                to: dir + "/session-1/subagents",
                name: "agent-abc.jsonl"
            )
            let report = DailyCostAggregator.claudeReport(projectsDirectory: dir)
            #expect(report.days.first?.outputTokens == 1200)
        }
    }

    /// A 1-hour cache write bills 1.6x a 5-minute write (2x vs 1.25x of input).
    @Test("Claude: 1h cache writes bill at a higher rate than 5m")
    func claudeChargesOneHourCacheHigher() throws {
        try withTempDirectory { dir in
            try write(
                [claudeLine(messageId: "a", requestId: "a", cacheWrite5m: 1_000_000)], to: dir,
                name: "a.jsonl")
            let fiveMinute = DailyCostAggregator.claudeReport(projectsDirectory: dir).totalCostUSD
            try FileManager.default.removeItem(atPath: dir + "/a.jsonl")

            try write(
                [claudeLine(messageId: "b", requestId: "b", cacheWrite1h: 1_000_000)], to: dir,
                name: "b.jsonl")
            let oneHour = DailyCostAggregator.claudeReport(projectsDirectory: dir).totalCostUSD

            // Sonnet 5: input $2 → 5m $2.50 / 1h $4.00
            #expect(abs(fiveMinute - 2.5) < 0.001)
            #expect(abs(oneHour - 4.0) < 0.001)
        }
    }

    /// A model with no known rate is reported as unsupported rather than silently
    /// folded in at zero cost.
    @Test("Claude: models without a rate appear in unsupportedModels")
    func claudeReportsUnsupportedModels() throws {
        try withTempDirectory { dir in
            try write(
                [claudeLine(messageId: "x", requestId: "x", model: "claude-unknown-9", output: 1000)],
                to: dir
            )
            let report = DailyCostAggregator.claudeReport(projectsDirectory: dir)
            #expect(report.unsupportedModels == ["claude-unknown-9"])
            #expect(report.totalCostUSD == 0)
        }
    }

    /// A date-suffixed model name (`claude-haiku-4-5-20251001`) still resolves to a rate.
    @Test("Claude: date-suffixed model names resolve in the rate table")
    func claudeNormalizesDatedModelNames() throws {
        try withTempDirectory { dir in
            try write(
                [
                    claudeLine(
                        messageId: "h", requestId: "h", model: "claude-haiku-4-5-20251001", output: 1_000_000)
                ],
                to: dir
            )
            let report = DailyCostAggregator.claudeReport(projectsDirectory: dir)
            #expect(report.unsupportedModels.isEmpty)
            // Haiku 4.5 output $5/Mtok
            #expect(abs(report.totalCostUSD - 5.0) < 0.001)
        }
    }

    // MARK: - Codex

    private func codexTokenCount(
        timestamp: String,
        input: Int,
        cached: Int = 0,
        output: Int
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count",\
        "info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
        "cache_write_input_tokens":0,"output_tokens":\(output),"total_tokens":\(input + output)}}}}
        """
    }

    /// `token_count` is cumulative and emitted twice per pair, so the aggregator takes
    /// the delta rather than summing.
    @Test("Codex: only the delta of total_token_usage is counted")
    func codexUsesMonotonicDelta() throws {
        try withTempDirectory { dir in
            try write(
                [
                    #"{"timestamp":"2026-07-20T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
                    codexTokenCount(timestamp: "2026-07-20T10:00:01.000Z", input: 100, output: 1_000_000),
                    // The same value again (the duplicate emission): delta 0, so nothing is counted.
                    codexTokenCount(timestamp: "2026-07-20T10:00:01.000Z", input: 100, output: 1_000_000),
                    // Only the growth in the cumulative total is added.
                    codexTokenCount(timestamp: "2026-07-20T10:00:02.000Z", input: 200, output: 2_000_000),
                ],
                to: dir
            )
            let report = DailyCostAggregator.codexReport(sessionsDirectory: dir)
            #expect(report.days.count == 1)
            // The final cumulative 2M, not the sum (4M).
            #expect(report.days.first?.outputTokens == 2_000_000)
            // gpt-5.3-codex output at $14/Mtok, so 2M = $28 (200 input tokens are noise)
            #expect(abs((report.days.first?.estimatedCostUSD ?? 0) - 28.0) < 0.01)
        }
    }

    /// A subagent rollout duplicates the parent history, so it is excluded wholesale.
    @Test("Codex: subagent rollouts are excluded to avoid double counting")
    func codexSkipsSubagentRollouts() throws {
        try withTempDirectory { dir in
            try write(
                [
                    #"{"timestamp":"2026-07-20T10:00:00.000Z","type":"session_meta","payload":{"id":"sub","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#,
                    #"{"timestamp":"2026-07-20T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
                    codexTokenCount(timestamp: "2026-07-20T10:00:01.000Z", input: 0, output: 1_000_000),
                ],
                to: dir
            )
            let report = DailyCostAggregator.codexReport(sessionsDirectory: dir)
            #expect(report.days.isEmpty)
        }
    }

    // MARK: - Report helpers

    /// Days without data are filled with 0 to keep the date axis continuous, so the
    /// chart's horizontal axis is not distorted.
    @Test("recentDaysFilled pads days without data with 0 for a continuous axis")
    func fillsMissingDays() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        let report = DailyCostReport(
            days: [
                DailyCost(day: threeDaysAgo, estimatedCostUSD: 12),
                DailyCost(day: today, estimatedCostUSD: 5),
            ],
            unsupportedModels: [],
            computedAt: now
        )

        let filled = report.recentDaysFilled(count: 4, now: now, calendar: calendar)
        #expect(filled.count == 4)
        #expect(filled.map(\.estimatedCostUSD) == [12, 0, 0, 5])
        #expect(filled.last?.day == today)
    }
}
