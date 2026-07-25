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

    // MARK: - tailContent

    @Test("tailContent reads only the tail and drops a possibly-incomplete first line")
    func tailContentReadsTail() throws {
        let lines = (0..<100).map { "line-\($0)-padding-padding-padding" }
        let content = lines.joined(separator: "\n") + "\n"
        let tmpPath = NSTemporaryDirectory() + "test-tail-\(UUID().uuidString).jsonl"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let tail = try #require(CodexUsageParser.tailContent(ofFileAt: tmpPath, maxBytes: 200))
        #expect(tail.contains("line-99-padding"))
        #expect(!tail.contains("line-0-padding-padding-padding\n"))
    }

    @Test("tailContent reads the full file when maxBytes exceeds file size")
    func tailContentReadsFullFileWhenSmall() throws {
        let content = "a\nb\nc\n"
        let tmpPath = NSTemporaryDirectory() + "test-tail-small-\(UUID().uuidString).jsonl"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let tail = try #require(CodexUsageParser.tailContent(ofFileAt: tmpPath, maxBytes: 1024))
        #expect(tail == content)
    }

    @Test("tailContent returns nil for a nonexistent file")
    func tailContentNilForMissingFile() {
        #expect(
            CodexUsageParser.tailContent(
                ofFileAt: "/tmp/nonexistent-\(UUID().uuidString).jsonl", maxBytes: 100
            ) == nil
        )
    }

    // MARK: - latestRolloutFile (YYYY/MM/DD 探索)

    @Test("latestRolloutFile walks year/month/day directories in descending order")
    func latestRolloutFileFindsNewestByDateDirectory() throws {
        let root = NSTemporaryDirectory() + "codex-sessions-\(UUID().uuidString)"
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: root) }

        let oldDir = root + "/2025/06/01"
        try fm.createDirectory(atPath: oldDir, withIntermediateDirectories: true)
        try "old".write(
            toFile: oldDir + "/rollout-2025-06-01T00-00-00-aaa.jsonl", atomically: true, encoding: .utf8
        )

        let newDir = root + "/2026/07/25"
        try fm.createDirectory(atPath: newDir, withIntermediateDirectories: true)
        try "newer".write(
            toFile: newDir + "/rollout-2026-07-25T02-00-00-bbb.jsonl", atomically: true, encoding: .utf8
        )
        try "newest".write(
            toFile: newDir + "/rollout-2026-07-25T03-00-00-ccc.jsonl", atomically: true, encoding: .utf8
        )

        let path = try #require(CodexUsageParser.latestRolloutFile(in: root))
        #expect(path.hasSuffix("rollout-2026-07-25T03-00-00-ccc.jsonl"))
    }

    @Test("latestRolloutFile returns nil when the sessions directory does not exist")
    func latestRolloutFileNilForMissingDirectory() {
        #expect(
            CodexUsageParser.latestRolloutFile(in: "/tmp/nonexistent-sessions-\(UUID().uuidString)") == nil
        )
    }

    // MARK: - latestSnapshot (tail read フォールバック挙動)

    @Test("latestSnapshot returns nil when token_count falls outside the tail chunk")
    func latestSnapshotFallsBackToNilWhenTokenCountOutsideTailChunk() throws {
        let root = NSTemporaryDirectory() + "codex-sessions-\(UUID().uuidString)"
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: root) }
        let dayDir = root + "/2026/07/25"
        try fm.createDirectory(atPath: dayDir, withIntermediateDirectories: true)

        let tokenCountLine = """
        {"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":50.0,"window_duration_mins":300,"resets_at":1},"secondary":null,"plan_type":"plus"}}}
        """
        let paddingLine = String(repeating: "x", count: 2000)
        // token_count は先頭に置き、その後に大量の padding 行を積んで tail チャンクの外に追い出す。
        let content = tokenCountLine + "\n"
            + Array(repeating: paddingLine, count: 50).joined(separator: "\n") + "\n"
        let path = dayDir + "/rollout-2026-07-25T00-00-00-zzz.jsonl"
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageParser.latestSnapshot(sessionsDirectory: root, tailBytes: 500)
        #expect(snapshot == nil)
    }

    @Test("latestSnapshot finds a token_count event within the tail chunk")
    func latestSnapshotFindsTokenCountWithinTailChunk() throws {
        let root = NSTemporaryDirectory() + "codex-sessions-\(UUID().uuidString)"
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: root) }
        let dayDir = root + "/2026/07/25"
        try fm.createDirectory(atPath: dayDir, withIntermediateDirectories: true)

        let paddingLine = String(repeating: "x", count: 100)
        let tokenCountLine = """
        {"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":50.0,"window_duration_mins":300,"resets_at":1},"secondary":null,"plan_type":"plus"}}}
        """
        let content = Array(repeating: paddingLine, count: 5).joined(separator: "\n")
            + "\n" + tokenCountLine + "\n"
        let path = dayDir + "/rollout-2026-07-25T00-00-00-zzz.jsonl"
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let snapshot = try #require(
            CodexUsageParser.latestSnapshot(sessionsDirectory: root, tailBytes: 100_000)
        )
        #expect(snapshot.primary?.usedPercent == 50.0)
    }
}
