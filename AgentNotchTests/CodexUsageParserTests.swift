import Foundation
import Testing
@testable import AgentNotchCore

@Suite("CodexUsageParser Tests")
struct CodexUsageParserTests {
    @Test("Parses rate_limits with non-null primary/secondary windows")
    func parsesFullRateLimits() throws {
        let line = """
        {"timestamp":"2026-07-24T17:51:37.231Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":25.0,"window_duration_mins":300,"resets_at":1774000000},"secondary":{"used_percent":18.5,"window_duration_mins":10080,"resets_at":1774600000},"credits":{"has_credits":true,"unlimited":false,"balance":null},"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}}}
        """
        let snapshot = try #require(CodexUsageParser.parseLine(line))
        #expect(snapshot.planType == "plus")
        let primary = try #require(snapshot.primary)
        #expect(primary.usedPercent == 25.0)
        #expect(primary.resetsAt == Date(timeIntervalSince1970: 1_774_000_000))
        let secondary = try #require(snapshot.secondary)
        #expect(secondary.usedPercent == 18.5)
    }

    @Test("Returns snapshot with nil windows for usage-based plan (business)")
    func handlesNullWindowsForUsageBasedPlan() throws {
        let line = """
        {"timestamp":"2026-07-24T17:51:37.231Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","limit_name":null,"primary":null,"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":null},"individual_limit":null,"spend_control_reached":null,"plan_type":"business","rate_limit_reached_type":null}}}
        """
        let snapshot = try #require(CodexUsageParser.parseLine(line))
        #expect(snapshot.planType == "business")
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
    }

    @Test("Ignores non token_count event types")
    func ignoresOtherEventTypes() {
        let line = """
        {"timestamp":"2026-07-24T17:51:37.231Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}
        """
        #expect(CodexUsageParser.parseLine(line) == nil)
    }

    @Test("Returns nil for malformed JSON line")
    func handlesMalformedLine() {
        #expect(CodexUsageParser.parseLine("not json") == nil)
        #expect(CodexUsageParser.parseLine("") == nil)
    }

    @Test("Scans lines from the end and returns the latest token_count event")
    func scansFromLatestLine() throws {
        let older = """
        {"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":10.0,"window_duration_mins":300,"resets_at":1},"secondary":null,"plan_type":"plus"}}}
        """
        let newer = """
        {"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":90.0,"window_duration_mins":300,"resets_at":2},"secondary":null,"plan_type":"plus"}}}
        """
        let unrelated = #"{"type":"event_msg","payload":{"type":"agent_message"}}"#

        let snapshot = try #require(
            CodexUsageParser.parseLatestRateLimits(fromLines: [older, unrelated, newer])
        )
        #expect(snapshot.primary?.usedPercent == 90.0)
    }
}
