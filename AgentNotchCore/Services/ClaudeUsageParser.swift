import Foundation

/// `api.anthropic.com/api/oauth/usage`（undocumented）のレスポンス JSON を
/// `ClaudeUsageSnapshot` にパースする。
///
/// # レスポンス構造（実データで確認）
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
/// # `limits` を主データ源にする理由
/// **モデル別の枠は `limits` 配列にしか現れない。** `seven_day_opus` / `seven_day_sonnet` 等の
/// キーは現在のレスポンスでは全て null で、実際のモデル別使用率（例: Fable 88%）は
/// `kind == "weekly_scoped"` の要素の `scope.model.display_name` と `percent` に入る。
/// `limits` は `severity` と `is_active`（今どの枠が効いているか）も持つので、
/// これを第一のデータ源にし、`five_hour` / `seven_day` / `seven_day_<model>` は
/// 旧形式・欠損時のフォールバックとして使う。
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
        // `~/.claude.json` の `cachedUsageUtilization` は同じ構造を `utilization` の下に持つ。
        let root = (json["utilization"] as? [String: Any]) ?? json

        var session = window(from: root["five_hour"] as? [String: Any])
        var weekAllModels = window(from: root["seven_day"] as? [String: Any])
        var weekModels: [ModelUsageWindow] = []

        // limits を優先して読む（モデル別枠・severity・is_active はここにしか無い）。
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
                let label = model?["display_name"] as? String
                    ?? (scope?["surface"] as? [String: Any])?["display_name"] as? String
                    ?? "Scoped"
                weekModels.append(ModelUsageWindow(modelLabel: label, window: parsed))
            default:
                continue
            }
        }

        // フォールバック: limits が無い旧形式では `seven_day_<model>` を使う。
        if weekModels.isEmpty {
            for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
                guard let raw = root[key] as? [String: Any],
                      let parsed = window(from: raw)
                else { continue }
                let label = key
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

    /// `limits[]` の 1 要素から `UsageWindow` を作る。
    private static func limitWindow(from entry: [String: Any]) -> UsageWindow? {
        guard let percent = number(entry["percent"]) else { return nil }
        return UsageWindow(
            usedPercent: normalizePercent(percent),
            resetsAt: (entry["resets_at"] as? String).flatMap(parseISO8601),
            severity: (entry["severity"] as? String).map(UsageSeverity.init(rawValue:)),
            isActive: entry["is_active"] as? Bool ?? false
        )
    }

    /// `five_hour` / `seven_day` / `seven_day_<model>` 形式から `UsageWindow` を作る。
    private static func window(from raw: [String: Any]?) -> UsageWindow? {
        guard let raw, let utilization = number(raw["utilization"]) else { return nil }
        return UsageWindow(
            usedPercent: normalizePercent(utilization),
            resetsAt: (raw["resets_at"] as? String).flatMap(parseISO8601)
        )
    }

    /// 追加クレジットの状況。`spend` に金額、`extra_usage` に有効/無効の理由が入る。
    private static func extraUsage(
        extraUsage: [String: Any]?,
        spend: [String: Any]?
    ) -> ExtraUsageInfo? {
        guard extraUsage != nil || spend != nil else { return nil }

        let used = money(spend?["used"])
        let limit = money(spend?["limit"]) ?? number(extraUsage?["monthly_limit"])
        let balance = money(spend?["balance"])
        let currency = (spend?["used"] as? [String: Any])?["currency"] as? String
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

    /// `{ "amount_minor": 1234, "currency": "USD", "exponent": 2 }` → 12.34。
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

    /// 0〜1 の比率で返ってくる場合があるので % に正規化する。
    private static func normalizePercent(_ value: Double) -> Double {
        value <= 1.0 && value > 0 ? value * 100 : value
    }
}
