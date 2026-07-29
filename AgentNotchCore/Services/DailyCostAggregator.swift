import Foundation

/// Aggregates estimated per-day cost from Claude Code and Codex local logs.
///
/// # Data sources (both unofficial and undocumented)
/// - Claude Code: `~/.claude/projects/**/*.jsonl`. Token breakdown in `message.usage`, model name
///   in `message.model`, time in `timestamp` (UTC). `costUSD` is not written, so the amount is
///   derived from the price table in `CostCalculator`.
/// - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. The `total_token_usage` of a
///   `token_count` event is a running total. The model name tracks the latest
///   `turn_context.payload.model`.
///
/// # Deduplication (essential: 51% of real entries are duplicates)
/// - **Claude**: one assistant message is split across several lines, one per content block
///   (thinking, text, and tool_use share a `message.id`). Keyed on `(message.id, requestId)`,
///   **the last line wins**; earlier lines are streaming placeholders with understated
///   output_tokens. Subagent logs (`<sessionId>/subagents/agent-*.jsonl`) use different message
///   ids and are not duplicates, so they **must be included** — excluding them loses more than
///   60% of the tokens.
/// - **Codex**: `token_count` is emitted twice in pairs, so naively summing `last_token_usage`
///   roughly doubles the total. Taking the **monotonic increments** of `total_token_usage` gives
///   the correct deltas. A subagent rollout duplicates the parent history, so files with
///   `session_meta.payload.source.subagent` are skipped.
///
/// # Performance
/// Measured on a debug build: about 4 seconds for 263MB across 319 files in `~/.claude/projects`,
/// and about 9 seconds for 987MB across 275 files in `~/.codex/sessions`. Before parsing JSON,
/// `Data.range(of:)` checks for a marker (`LineMarker`) and skips early, which greatly reduces how
/// much is parsed. A hand-written byte-scanning loop was 3x slower on a debug build and is not used.
///
/// This takes seconds, so it **must be called off the MainActor**. Calls are limited to while the
/// usage page is open (`DailyCostCoordinator`, 600-second interval by default).
public enum DailyCostAggregator {
    public static let defaultClaudeProjectsDirectory = NSHomeDirectory() + "/.claude/projects"
    public static let defaultCodexSessionsDirectory = NSHomeDirectory() + "/.codex/sessions"

    /// Per-day cost for Claude Code.
    public static func claudeReport(
        projectsDirectory: String = defaultClaudeProjectsDirectory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> DailyCostReport {
        let timestamps = TimestampParser()
        var accumulator = DayAccumulator(calendar: calendar)
        var unsupported: Set<String> = []
        // (message.id, requestId) to the last usage seen; among lines sharing a key, the last wins.
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
                    // Older formats give no breakdown, so everything falls back to 5m.
                    cacheWrite5m: write5m ?? (write1h == nil ? writeTotal : 0),
                    cacheWrite1h: write1h ?? 0,
                    cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0
                )

                let messageId = message["id"] as? String ?? ""
                let requestId = json["requestId"] as? String ?? ""
                let key =
                    messageId.isEmpty && requestId.isEmpty
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

    /// Per-day cost for Codex.
    public static func codexReport(
        sessionsDirectory: String = defaultCodexSessionsDirectory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> DailyCostReport {
        // Scanning every rollout under ~/.codex/sessions is exactly what the integration switch
        // governs, so an empty report is the honest answer while it is off.
        guard CodexAccess.isAllowed else {
            Log.usage.debug("Codex daily cost skipped: the Codex integration is off")
            return DailyCostReport(days: [], unsupportedModels: [], computedAt: now)
        }
        let timestamps = TimestampParser()
        var accumulator = DayAccumulator(calendar: calendar)
        var unsupported: Set<String> = []

        for path in jsonlFiles(under: sessionsDirectory) {
            guard let lines = lines(ofFileAt: path) else { continue }

            // A subagent rollout duplicates the parent history, so the whole file is skipped.
            // `session_meta` is always the first line, so only that line is examined.
            if let first = lines.first, first.contains(LineMarker.subagent),
                let json = try? JSONSerialization.jsonObject(with: first) as? [String: Any],
                json["type"] as? String == "session_meta",
                let payload = json["payload"] as? [String: Any],
                let source = payload["source"] as? [String: Any],
                source["subagent"] != nil
            {
                continue
            }

            var model = ""
            // total_token_usage is a running total, so only the delta from the previous value is added.
            var previous = CodexTotals()

            for line in lines {
                // Parse JSON only for the lines that need it; a single rollout can be tens of
                // thousands of lines and hundreds of megabytes. token_count is detected by
                // `_token_usage`, and the model is tracked via `"model"` in turn_context.
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

                // Codex counts cached_input_tokens within input, so it must not be added twice.
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

        /// Delta between running totals. If a reset happened (e.g. back to 0 for a new conversation), the current value is used as is.
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

    /// Per-day accumulation buffer. Timestamps are UTC and are mapped to the local day.
    private struct DayAccumulator {
        let calendar: Calendar
        private var byDay: [Date: DailyCost] = [:]

        init(calendar: Calendar) { self.calendar = calendar }

        mutating func add(
            day timestamp: Date, cost: Double, input: Int, output: Int, cacheWrite: Int, cacheRead: Int
        ) {
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

    /// Recursively enumerates the `.jsonl` files under a directory.
    static func jsonlFiles(under directory: String) -> [String] {
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            paths.append(url.path)
        }
        return paths
    }

    /// Reads a file split into lines. Avoiding `String` conversion and slice copies keeps peak
    /// memory and allocations down; `Data.SubSequence` is a `Data`, so it can be parsed directly.
    private static func lines(ofFileAt path: String) -> [Data.SubSequence]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    }

    /// Parser for ISO8601 timestamps.
    ///
    /// `ISO8601DateFormatter` is not `Sendable`, so it cannot be held in a static. Creating one per
    /// call is also too costly across tens of thousands of lines, so one local instance is created
    /// per aggregation run and reused.
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

/// Byte sequences used to skip lines quickly before parsing JSON. `Data.range(of:)` uses an
/// optimized substring search internally and beats a hand-written loop, especially in unoptimized
/// builds.
enum LineMarker {
    static let usage = Data("\"usage\"".utf8)
    static let totalTokenUsage = Data("_token_usage".utf8)
    static let model = Data("\"model\"".utf8)
    static let subagent = Data("\"subagent\"".utf8)
}

extension Data {
    /// Whether the line contains the `marker` byte sequence.
    fileprivate func contains(_ marker: Data) -> Bool {
        guard count >= marker.count else { return false }
        return range(of: marker) != nil
    }
}
