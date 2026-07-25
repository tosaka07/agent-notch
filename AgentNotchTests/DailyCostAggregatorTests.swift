import Foundation
import Testing

@testable import AgentNotchCore

/// 日毎コスト集計の重複排除・キャッシュ単価・Codex の累積差分をテストする。
@Suite("DailyCostAggregator Tests")
struct DailyCostAggregatorTests {
    /// 一時ディレクトリに jsonl を書いて集計させるヘルパ。
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

    /// 同一 assignment（message.id + requestId）が複数行に分割される場合、
    /// ストリーミング中のプレースホルダではなく**最後の行**を採用する。
    @Test("Claude: 同一 message.id の重複行は最後の行だけを数える")
    func claudeDeduplicatesKeepingLastEntry() throws {
        try withTempDirectory { dir in
            try write(
                [
                    // 同一キーで 3 行（thinking / text / tool_use 相当）。output が段階的に確定する。
                    claudeLine(messageId: "msg_1", requestId: "req_1", output: 6),
                    claudeLine(messageId: "msg_1", requestId: "req_1", output: 100),
                    claudeLine(messageId: "msg_1", requestId: "req_1", output: 1000),
                ],
                to: dir
            )
            let report = DailyCostAggregator.claudeReport(projectsDirectory: dir)

            #expect(report.days.count == 1)
            // 3 行合算（1106）ではなく最後の 1000 だけが採用される。
            #expect(report.days.first?.outputTokens == 1000)
            // Sonnet 5 の output $10/Mtok → 1000 tokens = $0.01
            #expect(abs((report.days.first?.estimatedCostUSD ?? 0) - 0.01) < 0.0001)
        }
    }

    /// subagent のログは別 message.id なので重複せず、含めないと取りこぼす。
    @Test("Claude: subagents 配下のログも集計対象に含める")
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

    /// 1 時間キャッシュ write は 5 分 write の 1.6 倍（input 比 2x vs 1.25x）で計上される。
    @Test("Claude: 1h キャッシュ write は 5m より高い単価で計上される")
    func claudeChargesOneHourCacheHigher() throws {
        try withTempDirectory { dir in
            try write([claudeLine(messageId: "a", requestId: "a", cacheWrite5m: 1_000_000)], to: dir, name: "a.jsonl")
            let fiveMinute = DailyCostAggregator.claudeReport(projectsDirectory: dir).totalCostUSD
            try FileManager.default.removeItem(atPath: dir + "/a.jsonl")

            try write([claudeLine(messageId: "b", requestId: "b", cacheWrite1h: 1_000_000)], to: dir, name: "b.jsonl")
            let oneHour = DailyCostAggregator.claudeReport(projectsDirectory: dir).totalCostUSD

            // Sonnet 5: input $2 → 5m $2.50 / 1h $4.00
            #expect(abs(fiveMinute - 2.5) < 0.001)
            #expect(abs(oneHour - 4.0) < 0.001)
        }
    }

    /// 単価が分からないモデルは 0 円として黙って混ぜず、未対応として報告する。
    @Test("Claude: 単価未対応モデルは unsupportedModels に載る")
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

    /// 日付サフィックス付きモデル名（`claude-haiku-4-5-20251001`）も単価に解決される。
    @Test("Claude: 日付サフィックス付きモデル名も単価テーブルに解決される")
    func claudeNormalizesDatedModelNames() throws {
        try withTempDirectory { dir in
            try write(
                [claudeLine(messageId: "h", requestId: "h", model: "claude-haiku-4-5-20251001", output: 1_000_000)],
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

    /// `token_count` は累積値かつペアで二重出力されるため、単純合算ではなく増分を取る。
    @Test("Codex: total_token_usage の累積差分だけを計上する")
    func codexUsesMonotonicDelta() throws {
        try withTempDirectory { dir in
            try write(
                [
                    #"{"timestamp":"2026-07-20T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
                    codexTokenCount(timestamp: "2026-07-20T10:00:01.000Z", input: 100, output: 1_000_000),
                    // 同じ値がもう一度出る（二重出力）→ 差分 0 なので計上されない。
                    codexTokenCount(timestamp: "2026-07-20T10:00:01.000Z", input: 100, output: 1_000_000),
                    // 累積が増えた分だけ足す。
                    codexTokenCount(timestamp: "2026-07-20T10:00:02.000Z", input: 200, output: 2_000_000),
                ],
                to: dir
            )
            let report = DailyCostAggregator.codexReport(sessionsDirectory: dir)
            #expect(report.days.count == 1)
            // 合算（4M）ではなく最終累積の 2M。
            #expect(report.days.first?.outputTokens == 2_000_000)
            // gpt-5.3-codex output $14/Mtok → 2M = $28（input 200 tokens は誤差）
            #expect(abs((report.days.first?.estimatedCostUSD ?? 0) - 28.0) < 0.01)
        }
    }

    /// subagent の rollout は親履歴を複製しているので丸ごと除外する。
    @Test("Codex: subagent の rollout は二重計上しないよう除外する")
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

    /// データが無い日も 0 で埋めて連続した日付軸にする（チャートの横軸が歪まないように）。
    @Test("recentDaysFilled はデータの無い日を 0 で埋めて連続日付にする")
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
