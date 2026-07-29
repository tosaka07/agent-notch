import Foundation

/// Reads the `rate_limits` from the most recent `token_count` event in a Codex CLI rollout JSONL
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
///
/// Codex writes the values it got from API response headers (`x-codex-primary-used-percent`, ...)
/// straight into the rollout, so rolling-window figures are available with no extra authentication
/// or API call. App Server is the primary usage source because older rollouts omit the
/// `individual_limit` used by usage-based plans; this parser remains the compatibility fallback.
///
/// # Performance
/// A rollout can grow to hundreds of megabytes, so:
/// - The search for the newest file walks the `YYYY/MM/DD` directory structure in descending order
///   and stops at the first hit; it never scans everything under `sessions` recursively.
/// - The file is not read in full. Only a fixed-size chunk at the end is read via `FileHandle`,
///   which is enough because `token_count` events appear near the end.
public enum CodexUsageParser {
    /// Number of trailing bytes read by the tail read.
    public static let defaultTailBytes = 256 * 1024

    /// Finds the newest rollout file under `~/.codex/sessions` and returns its latest rate_limits.
    /// Returns `nil` if the tail chunk contains no `token_count` event; the next poll retries.
    public static func latestSnapshot(
        sessionsDirectory: String = NSHomeDirectory() + "/.codex/sessions",
        tailBytes: Int = defaultTailBytes
    ) -> CodexUsageSnapshot? {
        guard let path = latestRolloutFile(in: sessionsDirectory) else { return nil }
        guard let content = tailContent(ofFileAt: path, maxBytes: tailBytes) else { return nil }
        return parseLatestRateLimits(fromLines: content.components(separatedBy: .newlines))
    }

    /// Walks `sessions/YYYY/MM/DD/rollout-*.jsonl` in descending year, month, day order and returns
    /// the newest file in the first date directory that contains one.
    /// Each level is enumerated one step at a time, so symlink cycles cannot affect it.
    static func latestRolloutFile(in sessionsDirectory: String) -> String? {
        let fm = FileManager.default
        for year in sortedDescendingSubdirectories(of: sessionsDirectory, fm: fm) {
            let yearDir = sessionsDirectory + "/" + year
            for month in sortedDescendingSubdirectories(of: yearDir, fm: fm) {
                let monthDir = yearDir + "/" + month
                for day in sortedDescendingSubdirectories(of: monthDir, fm: fm) {
                    let dayDir = monthDir + "/" + day
                    if let file = latestRolloutFile(inDayDirectory: dayDir, fm: fm) {
                        return file
                    }
                }
            }
        }
        return nil
    }

    /// Returns the immediate subdirectory names sorted descending (newest date first).
    /// `YYYY`/`MM`/`DD` are zero-padded and fixed-width, so a descending string sort is a
    /// descending date sort.
    private static func sortedDescendingSubdirectories(of path: String, fm: FileManager) -> [String] {
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return
            entries
            .filter { name in
                guard !name.hasPrefix(".") else { return false }
                var isDir: ObjCBool = false
                let full = path + "/" + name
                return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted(by: >)
    }

    /// Returns the path of the newest `.jsonl` file in a date directory (first by descending name).
    /// Rollout file names start with a timestamp, so a descending string sort puts the newest first.
    private static func latestRolloutFile(inDayDirectory dayDir: String, fm: FileManager) -> String? {
        guard let entries = try? fm.contentsOfDirectory(atPath: dayDir) else { return nil }
        guard let latest = entries.filter({ $0.hasSuffix(".jsonl") }).sorted(by: >).first else { return nil }
        return dayDir + "/" + latest
    }

    /// Reads up to `maxBytes` from the end of the file via `FileHandle` and returns it as UTF-8.
    /// A broken UTF-8 boundary only yields replacement characters rather than crashing
    /// (`String(decoding:as:)`). Unless the read started at byte zero, the first line is most
    /// likely a partial line and is discarded.
    static func tailContent(ofFileAt path: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }
        let readSize = min(UInt64(maxBytes), fileSize)
        let offset = fileSize - readSize
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        guard let data = try? handle.readToEnd() else { return nil }

        var content = String(decoding: data, as: UTF8.self)
        if offset > 0, let firstNewline = content.firstIndex(of: "\n") {
            content = String(content[content.index(after: firstNewline)...])
        }
        return content
    }

    /// Scans the JSONL lines from the end and parses the `rate_limits` of the first
    /// `token_count` event found.
    static func parseLatestRateLimits(fromLines lines: [String]) -> CodexUsageSnapshot? {
        for line in lines.reversed() {
            if let snapshot = parseLine(line) {
                return snapshot
            }
        }
        return nil
    }

    /// Parses one line of a rollout JSONL. Returns nil unless it is a `token_count` event.
    /// Public for testing.
    public static func parseLine(_ line: String) -> CodexUsageSnapshot? {
        guard !line.isEmpty,
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = json["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let rateLimits = payload["rate_limits"] as? [String: Any]
        else { return nil }
        return parse(rateLimits: rateLimits)
    }

    /// Parses a single `rate_limits` object. Public for testing.
    public static func parse(rateLimits: [String: Any]) -> CodexUsageSnapshot? {
        let planType = rateLimits["plan_type"] as? String
        let primary = window(from: rateLimits["primary"] as? [String: Any])
        let secondary = window(from: rateLimits["secondary"] as? [String: Any])
        let individualLimit = spendLimit(from: rateLimits["individual_limit"] as? [String: Any])
        guard primary != nil || secondary != nil || individualLimit != nil || planType != nil else {
            return nil
        }
        return CodexUsageSnapshot(
            primary: primary,
            secondary: secondary,
            planType: planType,
            individualLimit: individualLimit
        )
    }

    private static func window(from raw: [String: Any]?) -> UsageWindow? {
        guard let raw else { return nil }
        let percent: Double?
        if let d = raw["used_percent"] as? Double {
            percent = d
        } else if let i = raw["used_percent"] as? Int {
            percent = Double(i)
        } else {
            percent = nil
        }
        guard let percent else { return nil }

        var resetsAt: Date?
        if let epoch = raw["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let epochInt = raw["resets_at"] as? Int {
            resetsAt = Date(timeIntervalSince1970: Double(epochInt))
        }
        return UsageWindow(usedPercent: percent, resetsAt: resetsAt)
    }

    private static func spendLimit(from raw: [String: Any]?) -> CodexSpendLimit? {
        guard let raw,
            let used = decimal(from: raw["used"]),
            let limit = decimal(from: raw["limit"]),
            let remainingPercent = number(from: raw["remaining_percent"]),
            let resetsAt = number(from: raw["resets_at"])
        else { return nil }

        return CodexSpendLimit(
            used: used,
            limit: limit,
            remainingPercent: remainingPercent,
            resetsAt: Date(timeIntervalSince1970: resetsAt)
        )
    }

    private static func number(from raw: Any?) -> Double? {
        switch raw {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    private static func decimal(from raw: Any?) -> Decimal? {
        switch raw {
        case let value as Decimal:
            value
        case let value as NSNumber:
            value.decimalValue
        case let value as String:
            Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        default:
            nil
        }
    }
}
