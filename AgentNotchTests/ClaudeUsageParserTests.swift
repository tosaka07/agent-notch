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
        #expect(snapshot.weekModel?.usedPercent == 62.0)
        #expect(snapshot.weekModelLabel == "Fable")
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
