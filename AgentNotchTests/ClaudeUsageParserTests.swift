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

    /// In real responses every `seven_day_<model>` field is null, and per-model
    /// utilization only appears in the `limits` array under `weekly_scoped`
    /// (`scope.model.display_name`). `severity` and `is_active` live there too, so
    /// `limits` is the primary data source.
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

    /// `cachedUsageUtilization` in `~/.claude.json` nests the same structure under `utilization`.
    @Test("Unwraps a nested utilization object")
    func parsesNestedUtilization() throws {
        let json = """
            { "utilization": { "five_hour": { "utilization": 50, "resets_at": null } } }
            """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))
        #expect(snapshot.session?.usedPercent == 50)
    }

    /// Extra-credit (pay-as-you-go) amounts arrive as `spend.used` in minor units plus an exponent.
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

    /// Some plans return several `seven_day_<model>` fields — the legacy fallback for responses without `limits`.
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

    /// Utilization arrives as a 0-100 percentage. Regression test: values of 1 or
    /// less were once assumed to be a 0-1 ratio and multiplied by 100, so **1% read
    /// as 100%**. Because the gauge picks the largest limit as its representative,
    /// a session limit sitting at 1% appeared pinned to the maximum.
    @Test("Treats small utilization values as percentages, not 0-1 ratios")
    func smallValuesAreAlreadyPercentages() throws {
        // Verbatim shape of real data (cachedUsageUtilization in ~/.claude.json).
        let json = #"""
            {
              "five_hour": { "utilization": 1, "resets_at": null },
              "seven_day": { "utilization": 76, "resets_at": null }
            }
            """#
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))
        #expect(snapshot.session?.usedPercent == 1.0)
        #expect(snapshot.weekAllModels?.usedPercent == 76.0)
        // The gauge picks the largest limit; make sure 1% did not turn into 100%.
        let gauge = UsageSnapshot(claude: snapshot, codex: nil, fetchedAt: .now)
        #expect(gauge.primaryUsedPercent(for: .claudeCode) == 76.0)
    }

    @Test("Clamps out-of-range percentages")
    func clampsOutOfRange() throws {
        let json = #"{ "five_hour": { "utilization": 120, "resets_at": null } }"#
        let data = try #require(json.data(using: .utf8))
        let snapshot = try #require(ClaudeUsageParser.parse(data: data))
        #expect(snapshot.session?.usedPercent == 100.0)
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
