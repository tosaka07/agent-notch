import Foundation

/// `api.anthropic.com/api/oauth/usage`（undocumented）のレスポンス JSON を
/// `ClaudeUsageSnapshot` にパースする。
///
/// レスポンス例:
/// ```json
/// {
///   "five_hour": { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00Z" },
///   "seven_day": { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59Z" },
///   "seven_day_opus": { "utilization": 1.0, "resets_at": "..." },
///   "seven_day_sonnet": null
/// }
/// ```
/// `seven_day_<model>` はプラン・モデルによって存在有無/名前が変わるため、
/// `seven_day` 以外で `seven_day_` から始まり値が非 null の最初のキーを
/// 「Current week (Model)」として採用する。
public enum ClaudeUsageParser {
    private static func parseISO8601(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: s) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    public static func parse(data: Data) -> ClaudeUsageSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parse(json: json)
    }

    static func parse(json: [String: Any]) -> ClaudeUsageSnapshot? {
        let session = window(from: json["five_hour"] as? [String: Any])
        let weekAllModels = window(from: json["seven_day"] as? [String: Any])

        var weekModel: UsageWindow?
        var weekModelLabel: String?
        for key in json.keys.sorted() where key.hasPrefix("seven_day_") {
            guard let raw = json[key] as? [String: Any],
                  let parsed = window(from: raw)
            else { continue }
            weekModel = parsed
            weekModelLabel = key
                .replacingOccurrences(of: "seven_day_", with: "")
                .capitalized
            break
        }

        guard session != nil || weekAllModels != nil || weekModel != nil else { return nil }
        return ClaudeUsageSnapshot(
            session: session,
            weekAllModels: weekAllModels,
            weekModel: weekModel,
            weekModelLabel: weekModelLabel
        )
    }

    private static func window(from raw: [String: Any]?) -> UsageWindow? {
        guard let raw else { return nil }
        let utilization: Double?
        if let d = raw["utilization"] as? Double {
            utilization = d
        } else if let i = raw["utilization"] as? Int {
            utilization = Double(i)
        } else {
            utilization = nil
        }
        guard var percent = utilization else { return nil }
        // 0〜1 のレシオで返るケースを許容（保守的に 100 を超える値は弾く）。
        if percent <= 1.0 { percent *= 100 }
        guard percent >= 0, percent <= 100.5 else { return nil }
        percent = min(percent, 100)

        var resetsAt: Date?
        if let s = raw["resets_at"] as? String {
            resetsAt = parseISO8601(s)
        } else if let epoch = raw["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: epoch)
        }
        return UsageWindow(usedPercent: percent, resetsAt: resetsAt)
    }
}
