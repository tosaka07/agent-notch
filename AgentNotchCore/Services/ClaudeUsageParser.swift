import Foundation

/// Parses the response JSON of the undocumented `api.anthropic.com/api/oauth/usage`
/// endpoint into a `ClaudeUsageSnapshot`.
///
/// # Response shape (observed on real data)
/// ```json
/// {
///   "five_hour": { "utilization": 86, "resets_at": "...",
///                  "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
///   "seven_day": { "utilization": 68, "resets_at": "..." },
///   "seven_day_opus": null, "seven_day_sonnet": null, "seven_day_cowork": null,
///   "limits": [
///     { "kind": "session",       "group": "session", "percent": 86, "severity": "warning",
///       "resets_at": "...", "scope": null, "is_active": false },
///     { "kind": "weekly_all",    "group": "weekly",  "percent": 68, "severity": "normal", ... },
///     { "kind": "weekly_scoped", "group": "weekly",  "percent": 88, "severity": "warning",
///       "scope": { "model": { "id": null, "display_name": "Fable" } }, "is_active": true }
///   ],
///   "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, ... },
///   "spend": { "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
///              "limit": null, "percent": 0, "balance": null, "enabled": false, ... }
/// }
/// ```
///
/// # Why `limits` is the primary source
/// **Per-model windows appear only in the `limits` array.** The `seven_day_opus` /
/// `seven_day_sonnet` keys are all null in current responses; the real per-model percentages
/// (e.g. Fable 88%) live in the `scope.model.display_name` and `percent` of the
/// `kind == "weekly_scoped"` entries. `limits` also carries `severity` and `is_active` (which
/// window is currently binding), so it is read first, with `five_hour` / `seven_day` /
/// `seven_day_<model>` kept as a fallback for the older shape and for missing data.
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
        // `cachedUsageUtilization` in `~/.claude.json` nests the same structure under `utilization`.
        let root = (json["utilization"] as? [String: Any]) ?? json

        var session = window(from: root["five_hour"] as? [String: Any])
        var weekAllModels = window(from: root["seven_day"] as? [String: Any])
        var weekModels: [ModelUsageWindow] = []

        // Read limits first; per-model windows, severity, and is_active exist nowhere else.
        for entry in root["limits"] as? [[String: Any]] ?? [] {
            guard let parsed = limitWindow(from: entry) else { continue }
            switch entry["kind"] as? String {
            case "session":
                session = parsed
            case "weekly_all":
                weekAllModels = parsed
            case "weekly_scoped":
                let scope = entry["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let label =
                    model?["display_name"] as? String
                    ?? (scope?["surface"] as? [String: Any])?["display_name"] as? String
                    ?? "Scoped"
                weekModels.append(ModelUsageWindow(modelLabel: label, window: parsed))
            default:
                continue
            }
        }

        // Fallback: the older shape has no limits, so use `seven_day_<model>`.
        if weekModels.isEmpty {
            for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
                guard let raw = root[key] as? [String: Any],
                    let parsed = window(from: raw)
                else { continue }
                let label =
                    key
                    .replacingOccurrences(of: "seven_day_", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                weekModels.append(ModelUsageWindow(modelLabel: label, window: parsed))
            }
        }

        let extra = extraUsage(
            extraUsage: root["extra_usage"] as? [String: Any],
            spend: root["spend"] as? [String: Any]
        )

        guard session != nil || weekAllModels != nil || !weekModels.isEmpty else { return nil }
        return ClaudeUsageSnapshot(
            session: session,
            weekAllModels: weekAllModels,
            weekModels: weekModels,
            extraUsage: extra
        )
    }

    /// Builds a `UsageWindow` from one `limits[]` entry.
    private static func limitWindow(from entry: [String: Any]) -> UsageWindow? {
        guard let percent = number(entry["percent"]) else { return nil }
        return UsageWindow(
            usedPercent: normalizePercent(percent),
            resetsAt: (entry["resets_at"] as? String).flatMap(parseISO8601),
            severity: (entry["severity"] as? String).map(UsageSeverity.init(rawValue:)),
            isActive: entry["is_active"] as? Bool ?? false
        )
    }

    /// Builds a `UsageWindow` from the `five_hour` / `seven_day` / `seven_day_<model>` shape.
    private static func window(from raw: [String: Any]?) -> UsageWindow? {
        guard let raw, let utilization = number(raw["utilization"]) else { return nil }
        return UsageWindow(
            usedPercent: normalizePercent(utilization),
            resetsAt: (raw["resets_at"] as? String).flatMap(parseISO8601)
        )
    }

    /// Extra-credit state. `spend` holds the amounts, `extra_usage` holds the enabled/disabled reason.
    private static func extraUsage(
        extraUsage: [String: Any]?,
        spend: [String: Any]?
    ) -> ExtraUsageInfo? {
        guard extraUsage != nil || spend != nil else { return nil }

        let used = money(spend?["used"])
        let limit = money(spend?["limit"]) ?? number(extraUsage?["monthly_limit"])
        let balance = money(spend?["balance"])
        let currency =
            (spend?["used"] as? [String: Any])?["currency"] as? String
            ?? extraUsage?["currency"] as? String

        return ExtraUsageInfo(
            isEnabled: (spend?["enabled"] as? Bool) ?? (extraUsage?["is_enabled"] as? Bool) ?? false,
            usedAmount: used,
            limitAmount: limit,
            balanceAmount: balance,
            currency: currency,
            usedPercent: number(spend?["percent"]) ?? number(extraUsage?["utilization"]),
            disabledReason: spend?["disabled_reason"] as? String
                ?? extraUsage?["disabled_reason"] as? String,
            spendLimitReached: (spend?["spend_limit_reached"] as? Bool)
                ?? (extraUsage?["spend_limit_reached"] as? Bool) ?? false
        )
    }

    /// Converts `{ "amount_minor": 1234, "currency": "USD", "exponent": 2 }` to 12.34.
    private static func money(_ raw: Any?) -> Double? {
        if let dict = raw as? [String: Any] {
            guard let minor = number(dict["amount_minor"]) else { return nil }
            let exponent = number(dict["exponent"]) ?? 2
            return minor / pow(10, exponent)
        }
        return number(raw)
    }

    private static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Usage is always treated as a **percentage from 0 to 100**, never as a 0-1 ratio.
    ///
    /// Real responses (`cachedUsageUtilization` in `~/.claude.json` and the undocumented API)
    /// return integer percentages such as `"percent": 76` or `"utilization": 1`. Scaling small
    /// values by 100 on the assumption that they might be ratios would turn a genuine 1% into
    /// 100%, and since the gauge picks the largest window as its representative, the session
    /// window would appear pinned at its limit.
    private static func normalizePercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
