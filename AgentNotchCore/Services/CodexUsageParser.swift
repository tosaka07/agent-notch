import Foundation

/// Codex CLI の rollout jsonl（`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`）から
/// 直近の `token_count` イベントに載っている `rate_limits` を読み取る。
///
/// Codex 本体が API レスポンスヘッダー（`x-codex-primary-used-percent` 等）から得た値を
/// そのまま rollout に書き出しているため、追加の認証・API 呼び出し無しで正確な値が取れる。
/// ただし usage-based（従量課金）プランでは primary/secondary が null になる。
public enum CodexUsageParser {
    /// `~/.codex/sessions` 配下から最新の rollout ファイルを探し、直近の rate_limits を返す。
    public static func latestSnapshot(
        sessionsDirectory: String = NSHomeDirectory() + "/.codex/sessions"
    ) -> CodexUsageSnapshot? {
        guard let path = latestRolloutFile(in: sessionsDirectory) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8)
        else { return nil }
        return parseLatestRateLimits(fromLines: content.components(separatedBy: .newlines))
    }

    /// ディレクトリ配下（再帰）で最終更新時刻が最も新しい `.jsonl` ファイルのパスを返す。
    static func latestRolloutFile(in directory: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return nil }

        var bestPath: String?
        var bestMTime: Date = .distantPast
        for case let relPath as String in enumerator {
            guard relPath.hasSuffix(".jsonl") else { continue }
            let fullPath = directory + "/" + relPath
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let mtime = attrs[.modificationDate] as? Date
            else { continue }
            if mtime > bestMTime {
                bestMTime = mtime
                bestPath = fullPath
            }
        }
        return bestPath
    }

    /// jsonl の行配列を末尾から走査し、最初に見つかった `token_count` イベントの
    /// `rate_limits` をパースして返す。
    static func parseLatestRateLimits(fromLines lines: [String]) -> CodexUsageSnapshot? {
        for line in lines.reversed() {
            if let snapshot = parseLine(line) {
                return snapshot
            }
        }
        return nil
    }

    /// rollout jsonl の 1 行をパースする。`token_count` イベントでなければ nil。
    /// テスト用に public にしている。
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

    /// `rate_limits` オブジェクト 1 件分をパースする。テスト用に public にしている。
    public static func parse(rateLimits: [String: Any]) -> CodexUsageSnapshot? {
        let planType = rateLimits["plan_type"] as? String
        let primary = window(from: rateLimits["primary"] as? [String: Any])
        let secondary = window(from: rateLimits["secondary"] as? [String: Any])
        guard primary != nil || secondary != nil || planType != nil else { return nil }
        return CodexUsageSnapshot(primary: primary, secondary: secondary, planType: planType)
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
}
