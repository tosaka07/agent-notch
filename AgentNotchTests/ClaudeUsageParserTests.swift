import Foundation
import Testing
@testable import AgentNotchCore

@Suite("ClaudeUsageParser Tests")
struct ClaudeUsageParserTests {
    @Test("Parses five_hour, seven_day and a per-model seven_day window")
    func parsesFullResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 100.0, "resets_at": "2026-07-26T02:09:00+09:00" },
          "seven_day": { "utilization": 46.0, "resets_at": "2026-07-26T18:59:00+09:00" },
          "seven_day_fable": { "utilization": 62.0, "resets_at": "2026-07-26T18:59:00+09:00" },
          "seven_day_sonnet": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))

        #expect(snapshot.session?.usedPercent == 100.0)
        #expect(snapshot.weekAllModels?.usedPercent == 46.0)
        #expect(snapshot.weekModels.count == 1)
        #expect(snapshot.weekModels.first?.window.usedPercent == 62.0)
        #expect(snapshot.weekModels.first?.modelLabel == "Fable")
    }

    /// 実際のレスポンスでは `seven_day_<model>` は全て null で、モデル別の使用率は
    /// `limits` 配列の `weekly_scoped` にしか現れない（`scope.model.display_name`）。
    /// `severity` / `is_active` もここにしか無いので、limits を主データ源にする。
    @Test("Reads session/weekly/per-model windows from the limits array")
    func parsesLimitsArray() throws {
        let json = """
        {
          "five_hour": { "utilization": 86, "resets_at": "2026-07-25T07:50:00.152795+00:00" },
          "seven_day": { "utilization": 68, "resets_at": "2026-07-26T10:00:00.152817+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "limits": [
            { "kind": "session", "group": "session", "percent": 86, "severity": "warning",
              "resets_at": "2026-07-25T07:50:00.152795+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_all", "group": "weekly", "percent": 68, "severity": "normal",
              "resets_at": "2026-07-26T10:00:00.152817+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 88, "severity": "warning",
              "resets_at": "2026-07-26T10:00:00.153148+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" } }, "is_active": true }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))

        #expect(snapshot.session?.usedPercent == 86)
        #expect(snapshot.session?.severity == .warning)
        #expect(snapshot.weekAllModels?.usedPercent == 68)
        #expect(snapshot.weekAllModels?.severity == .normal)
        #expect(snapshot.weekModels.count == 1)
        #expect(snapshot.weekModels.first?.modelLabel == "Fable")
        #expect(snapshot.weekModels.first?.window.usedPercent == 88)
        #expect(snapshot.weekModels.first?.window.isActive == true)
    }

    /// `~/.claude.json` の `cachedUsageUtilization` は同じ構造を `utilization` の下に持つ。
    @Test("Unwraps a nested utilization object")
    func parsesNestedUtilization() throws {
        let json = """
        { "utilization": { "five_hour": { "utilization": 50, "resets_at": null } } }
        """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))
        #expect(snapshot.session?.usedPercent == 50)
    }

    /// 追加クレジット（従量課金）の金額は `spend.used` の minor unit + exponent で入る。
    @Test("Parses extra credit amounts from spend")
    func parsesExtraUsage() throws {
        let json = """
        {
          "five_hour": { "utilization": 10, "resets_at": null },
          "extra_usage": { "is_enabled": true, "currency": "USD", "disabled_reason": null },
          "spend": {
            "used": { "amount_minor": 1234, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 5000, "currency": "USD", "exponent": 2 },
            "balance": { "amount_minor": 3766, "currency": "USD", "exponent": 2 },
            "percent": 25, "enabled": true, "spend_limit_reached": false
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))
        let extra = try #require(snapshot.extraUsage)

        #expect(extra.isEnabled)
        #expect(extra.usedAmount == 12.34)
        #expect(extra.limitAmount == 50.0)
        #expect(extra.balanceAmount == 37.66)
        #expect(extra.usedPercent == 25)
        #expect(extra.currency == "USD")
    }

    /// プランによっては `seven_day_<model>` が複数返る（limits が無い旧形式のフォールバック）。
    @Test("Keeps every per-model seven_day window, not just the first one")
    func parsesMultiplePerModelWindows() throws {
        let json = """
        {
          "seven_day": { "utilization": 46.0, "resets_at": null },
          "seven_day_fable": { "utilization": 62.0, "resets_at": null },
          "seven_day_opus": { "utilization": 11.0, "resets_at": null },
          "seven_day_haiku": null
        }
        """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))

        #expect(snapshot.weekModels.count == 2)
        #expect(snapshot.weekModels.map(\.modelLabel) == ["Fable", "Opus"])
        #expect(snapshot.weekModels.map(\.window.usedPercent) == [62.0, 11.0])
    }

    @Test("Converts a 0-1 ratio utilization into a percentage")
    func convertsRatioUtilization() throws {
        let json = #"{ "five_hour": { "utilization": 0.33, "resets_at": null } }"#
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))
        #expect(snapshot.session?.usedPercent == 33.0)
        #expect(snapshot.session?.resetsAt == nil)
    }

    @Test("Returns nil when no known window keys are present")
    func returnsNilForEmptyPayload() throws {
        let json = #"{ "extra_usage": { "is_enabled": false } }"#
        let data = try #require(json.data(using: .utf8))
        #expect(ClaudeUsageParser.parse(data: data) == nil)
    }

    @Test("Returns nil for malformed JSON")
    func returnsNilForMalformedJSON() {
        let data = Data("not json".utf8)
        #expect(ClaudeUsageParser.parse(data: data) == nil)
    }
}
