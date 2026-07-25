import Foundation

/// Claude Code / Codex のローカルログから日毎の推定コストを集計する。
///
/// # データ源（いずれも非公式・非文書化）
/// - Claude Code: `~/.claude/projects/**/*.jsonl`。`message.usage` にトークン内訳、
///   `message.model` にモデル名、`timestamp`（UTC）に時刻が入る。`costUSD` は書かれないので
///   単価テーブル（`CostCalculator`）から換算する。
/// - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`。`token_count` イベントの
///   `total_token_usage` が累積値。モデル名は直近の `turn_context.payload.model` を追う。
///
/// # 重複排除（実データで 51% が重複するため必須）
/// - **Claude**: 1 つの assistant メッセージが content block ごとに複数行へ分割される
///   （thinking / text / tool_use が同じ `message.id`）。`(message.id, requestId)` をキーに
///   **最後の行を採用**する。前の行はストリーミング中のプレースホルダで output_tokens が過小。
///   subagent のログ（`<sessionId>/subagents/agent-*.jsonl`）は別 message.id で重複しないため
///   **必ず含める**（除外すると 6 割以上のトークンを取りこぼす）。
/// - **Codex**: `token_count` がペアで二重出力されるため、`last_token_usage` の単純合算は
///   約 2 倍になる。`total_token_usage` の**単調増分**を取ることで正確な差分が得られる。
///   subagent の rollout は親履歴を複製するので `session_meta.payload.source.subagent` があれば除外。
///
/// # パフォーマンス
/// 実測（debug ビルド）: `~/.claude/projects` 263MB / 319 ファイルで約 4 秒、
/// `~/.codex/sessions` 987MB / 275 ファイルで約 9 秒。JSON パース前に
/// `Data.range(of:)` でマーカー（`LineMarker`）の有無を見て早期スキップし、
/// パース対象を大幅に減らしている（自前のバイト走査ループは debug ビルドでは
/// かえって 3 倍遅くなったので使わない）。
///
/// 数秒かかるので**必ず off-MainActor で呼ぶこと**。呼び出しは使用量ページを
/// 開いている間だけ（`DailyCostCoordinator`、既定 600 秒間隔）に絞っている。
public enum DailyCostAggregator {
    public static let defaultClaudeProjectsDirectory = NSHomeDirectory() + "/.claude/projects"
    public static let defaultCodexSessionsDirectory = NSHomeDirectory() + "/.codex/sessions"

    /// Claude Code の日毎コスト。
    public static func claudeReport(
        projectsDirectory: String = defaultClaudeProjectsDirectory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> DailyCostReport {
        let timestamps = TimestampParser()
        var accumulator = DayAccumulator(calendar: calendar)
        var unsupported: Set<String> = []
        // (message.id, requestId) → 最後に見た usage。同一キーの複数行は最後を採用する。
        var latestByKey: [String: ClaudeEntry] = [:]

        for path in jsonlFiles(under: projectsDirectory) {
            guard let lines = lines(ofFileAt: path) else { continue }
            for line in lines {
                guard line.contains(LineMarker.usage),
                      let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = json["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = (json["timestamp"] as? String).flatMap(timestamps.date(from:))
                else { continue }

                let model = message["model"] as? String ?? ""
                guard model != "<synthetic>" else { continue }

                let cacheCreation = usage["cache_creation"] as? [String: Any]
                let write1h = cacheCreation?["ephemeral_1h_input_tokens"] as? Int
                let write5m = cacheCreation?["ephemeral_5m_input_tokens"] as? Int
                let writeTotal = usage["cache_creation_input_tokens"] as? Int ?? 0

                let entry = ClaudeEntry(
                    timestamp: timestamp,
                    model: model,
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    // 内訳が取れない古い形式では全量を 5m 扱いにフォールバックする。
                    cacheWrite5m: write5m ?? (write1h == nil ? writeTotal : 0),
                    cacheWrite1h: write1h ?? 0,
                    cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0
                )

                let messageId = message["id"] as? String ?? ""
                let requestId = json["requestId"] as? String ?? ""
                let key = messageId.isEmpty && requestId.isEmpty
                    ? UUID().uuidString
                    : "\(messageId):\(requestId)"
                latestByKey[key] = entry
            }
        }

        for entry in latestByKey.values {
            let cost = CostCalculator.estimateCost(
                model: entry.model,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheWrite5mTokens: entry.cacheWrite5m,
                cacheWrite1hTokens: entry.cacheWrite1h,
                cacheReadTokens: entry.cacheRead,
                at: entry.timestamp
            )
            if cost == nil { unsupported.insert(entry.model) }
            accumulator.add(
                day: entry.timestamp,
                cost: cost ?? 0,
                input: entry.inputTokens,
                output: entry.outputTokens,
                cacheWrite: entry.cacheWrite5m + entry.cacheWrite1h,
                cacheRead: entry.cacheRead
            )
        }

        return DailyCostReport(
            days: accumulator.sortedDays(),
            unsupportedModels: unsupported.sorted(),
            computedAt: now
        )
    }

    /// Codex の日毎コスト。
    public static func codexReport(
        sessionsDirectory: String = defaultCodexSessionsDirectory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> DailyCostReport {
        let timestamps = TimestampParser()
        var accumulator = DayAccumulator(calendar: calendar)
        var unsupported: Set<String> = []

        for path in jsonlFiles(under: sessionsDirectory) {
            guard let lines = lines(ofFileAt: path) else { continue }

            // subagent の rollout は親履歴を複製しているのでファイルごと捨てる。
            // `session_meta` は必ず先頭行なので、全行を走査せず 1 行目だけ見る。
            if let first = lines.first, first.contains(LineMarker.subagent),
               let json = try? JSONSerialization.jsonObject(with: first) as? [String: Any],
               json["type"] as? String == "session_meta",
               let payload = json["payload"] as? [String: Any],
               let source = payload["source"] as? [String: Any],
               source["subagent"] != nil {
                continue
            }

            var model = ""
            // total_token_usage は累積値なので、前回との差分だけを足す。
            var previous = CodexTotals()

            for line in lines {
                // JSON パースは必要な行だけに絞る（rollout は 1 ファイル数万行・数百 MB になり得る）。
                // token_count の判定は `_token_usage`、モデル追跡は turn_context の `"model"` で拾う。
                guard line.contains(LineMarker.totalTokenUsage) || line.contains(LineMarker.model)
                else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = json["payload"] as? [String: Any]
                else { continue }

                if let turnModel = payload["model"] as? String, !turnModel.isEmpty {
                    model = turnModel
                }
                guard payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let totals = info["total_token_usage"] as? [String: Any],
                      let timestamp = (json["timestamp"] as? String).flatMap(timestamps.date(from:))
                else { continue }

                let current = CodexTotals(
                    input: totals["input_tokens"] as? Int ?? 0,
                    cachedInput: totals["cached_input_tokens"] as? Int ?? 0,
                    cacheWrite: totals["cache_write_input_tokens"] as? Int ?? 0,
                    output: totals["output_tokens"] as? Int ?? 0
                )
                let delta = current.delta(from: previous)
                previous = current
                guard delta.hasTokens else { continue }

                // Codex の cached_input_tokens は input に含まれる内数なので二重計上しない。
                let freshInput = max(0, delta.input - delta.cachedInput)
                let cost = CostCalculator.estimateCost(
                    model: model,
                    inputTokens: freshInput,
                    outputTokens: delta.output,
                    cacheWrite5mTokens: delta.cacheWrite,
                    cacheReadTokens: delta.cachedInput,
                    at: timestamp
                )
                if cost == nil, !model.isEmpty { unsupported.insert(model) }
                accumulator.add(
                    day: timestamp,
                    cost: cost ?? 0,
                    input: freshInput,
                    output: delta.output,
                    cacheWrite: delta.cacheWrite,
                    cacheRead: delta.cachedInput
                )
            }
        }

        return DailyCostReport(
            days: accumulator.sortedDays(),
            unsupportedModels: unsupported.sorted(),
            computedAt: now
        )
    }

    // MARK: - Internals

    private struct ClaudeEntry {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheWrite5m: Int
        let cacheWrite1h: Int
        let cacheRead: Int
    }

    private struct CodexTotals {
        var input = 0
        var cachedInput = 0
        var cacheWrite = 0
        var output = 0

        var hasTokens: Bool { input > 0 || output > 0 || cacheWrite > 0 || cachedInput > 0 }

        /// 累積値の差分。リセット（新しい会話で 0 に戻る等）が起きたら現在値をそのまま使う。
        func delta(from previous: CodexTotals) -> CodexTotals {
            guard input >= previous.input, output >= previous.output else { return self }
            return CodexTotals(
                input: input - previous.input,
                cachedInput: max(0, cachedInput - previous.cachedInput),
                cacheWrite: max(0, cacheWrite - previous.cacheWrite),
                output: output - previous.output
            )
        }
    }

    /// 日単位の集計バッファ。タイムスタンプは UTC なのでローカル日に落とす。
    private struct DayAccumulator {
        let calendar: Calendar
        private var byDay: [Date: DailyCost] = [:]

        init(calendar: Calendar) { self.calendar = calendar }

        mutating func add(day timestamp: Date, cost: Double, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) {
            let day = calendar.startOfDay(for: timestamp)
            let existing = byDay[day]
            byDay[day] = DailyCost(
                day: day,
                estimatedCostUSD: (existing?.estimatedCostUSD ?? 0) + cost,
                inputTokens: (existing?.inputTokens ?? 0) + input,
                outputTokens: (existing?.outputTokens ?? 0) + output,
                cacheWriteTokens: (existing?.cacheWriteTokens ?? 0) + cacheWrite,
                cacheReadTokens: (existing?.cacheReadTokens ?? 0) + cacheRead
            )
        }

        func sortedDays() -> [DailyCost] {
            byDay.values.sorted { $0.day < $1.day }
        }
    }

    /// ディレクトリ配下の `.jsonl` を再帰的に列挙する。
    static func jsonlFiles(under directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            paths.append(url.path)
        }
        return paths
    }

    /// ファイルを行単位に分割して読む。`String` 化とスライスのコピーを避けてメモリピークと
    /// アロケーションを抑える（`Data.SubSequence` は `Data` なのでそのまま JSON パースできる）。
    private static func lines(ofFileAt path: String) -> [Data.SubSequence]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    }

    /// ISO8601 タイムスタンプのパーサ。
    ///
    /// `ISO8601DateFormatter` は `Sendable` ではないので static に持てない。一方で
    /// 数万行を処理するため呼び出しごとの生成も避けたい。集計 1 回につき 1 インスタンスを
    /// ローカルで作って使い回す。
    struct TimestampParser {
        private let fractional: ISO8601DateFormatter
        private let plain: ISO8601DateFormatter

        init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
        }

        func date(from string: String) -> Date? {
            fractional.date(from: string) ?? plain.date(from: string)
        }
    }
}

/// JSON パース前の高速スキップに使うバイト列。`Data.range(of:)` は内部で最適化された
/// 部分列探索を使うため、自前のループより（特に最適化なしビルドで）速い。
enum LineMarker {
    static let usage = Data("\"usage\"".utf8)
    static let totalTokenUsage = Data("_token_usage".utf8)
    static let model = Data("\"model\"".utf8)
    static let subagent = Data("\"subagent\"".utf8)
}

private extension Data {
    /// 行に `marker` のバイト列が含まれるか。
    func contains(_ marker: Data) -> Bool {
        guard count >= marker.count else { return false }
        return range(of: marker) != nil
    }
}
