import Foundation
import Testing

@testable import AgentNotchCore

@Suite("TranscriptParser Tests")
struct TranscriptParserTests {
    /// Usage is nested under `message.usage`; there is no top-level `usage` field
    /// (confirmed against real data). Regression test: an earlier version assumed the
    /// top level and therefore never caught a parser that always returned 0.
    @Test("Parses cumulative token usage from JSONL transcript")
    func parseCumulativeUsage() throws {
        let lines = [
            #"{"type":"assistant","requestId":"req_1","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":5}}}"#,
            #"{"type":"assistant","requestId":"req_2","message":{"id":"msg_2","usage":{"input_tokens":200,"output_tokens":80,"cache_creation_input_tokens":0,"cache_read_input_tokens":20}}}"#,
        ]
        let content = lines.joined(separator: "\n")
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let usage = TranscriptParser.parseCumulativeUsage(at: tmpPath)
        #expect(usage.inputTokens == 300)
        #expect(usage.outputTokens == 130)
        #expect(usage.cacheCreationTokens == 10)
        #expect(usage.cacheReadTokens == 25)
        #expect(usage.totalTokens == 430)
        #expect(usage.cachedTokens == 35)
    }

    /// A single assistant message is split across lines, one per content block —
    /// thinking, text, and tool_use each get their own line under the same
    /// `message.id` / `requestId`. Summing them would inflate usage two- to
    /// threefold, so only the last line counts.
    @Test("Deduplicates rows that share message.id and requestId, keeping the last")
    func deduplicatesSplitRows() throws {
        let lines = [
            #"{"requestId":"req_1","message":{"id":"msg_1","usage":{"input_tokens":2,"output_tokens":6,"cache_read_input_tokens":46025}}}"#,
            #"{"requestId":"req_1","message":{"id":"msg_1","usage":{"input_tokens":2,"output_tokens":4774,"cache_read_input_tokens":46025}}}"#,
        ]
        let content = lines.joined(separator: "\n")
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let usage = TranscriptParser.parseCumulativeUsage(at: tmpPath)
        #expect(usage.outputTokens == 4774)
        #expect(usage.cacheReadTokens == 46025)
    }

    @Test("Returns empty usage for nonexistent file")
    func nonexistentFile() {
        let usage = TranscriptParser.parseCumulativeUsage(at: "/tmp/nonexistent-\(UUID().uuidString).jsonl")
        #expect(usage.inputTokens == 0)
        #expect(usage.outputTokens == 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("Skips lines without usage field")
    func skipsNonUsageLines() throws {
        let lines = [
            #"{"type":"user","message":"hello"}"#,
            #"{"type":"assistant","requestId":"req_1","message":{"id":"msg_1","usage":{"input_tokens":50,"output_tokens":25}}}"#,
            #"{"type":"tool_result","content":"ok"}"#,
        ]
        let content = lines.joined(separator: "\n")
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let usage = TranscriptParser.parseCumulativeUsage(at: tmpPath)
        #expect(usage.inputTokens == 50)
        #expect(usage.outputTokens == 25)
    }

    @Test("Handles empty file gracefully")
    func emptyFile() throws {
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try "".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let usage = TranscriptParser.parseCumulativeUsage(at: tmpPath)
        #expect(usage.totalTokens == 0)
    }

    @Test("firstUserMessage extracts first user content string")
    func firstUserMessageString() throws {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"Fix the auth bug"},"sessionId":"s1"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"OK"}]}}"#,
        ]
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try lines.joined(separator: "\n").write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let msg = TranscriptParser.firstUserMessage(at: tmpPath)
        #expect(msg == "Fix the auth bug")
    }

    @Test("firstUserMessage extracts from content array")
    func firstUserMessageArray() throws {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add tests"}]},"sessionId":"s1"}"#
        ]
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try lines.joined(separator: "\n").write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let msg = TranscriptParser.firstUserMessage(at: tmpPath)
        #expect(msg == "Add tests")
    }

    @Test("firstUserMessage returns nil for empty transcript")
    func firstUserMessageEmpty() throws {
        let tmpPath = NSTemporaryDirectory() + "test-transcript-\(UUID().uuidString).jsonl"
        try "".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        #expect(TranscriptParser.firstUserMessage(at: tmpPath) == nil)
    }

    // MARK: - sanitizeUserPromptText (image reference markers)

    /// The marker text is localized, so it is derived at runtime from a known input
    /// rather than hardcoded — a literal would only match one system locale.
    private static let singleImageMarker =
        TranscriptParser.sanitizeUserPromptText("[Image: source: /a.png]") ?? ""

    @Test("sanitizeUserPromptText replaces a single image reference block with a marker")
    func sanitizeSingleImageOnly() {
        let marker = Self.singleImageMarker
        #expect(marker.hasPrefix("[") && marker.hasSuffix("]"))
        // The file path must not leak into the marker.
        #expect(!marker.contains("/a.png"))
        #expect(!marker.contains("source"))
    }

    @Test("sanitizeUserPromptText keeps surrounding text and replaces the image block")
    func sanitizeImageMixedWithText() {
        let text = "Look at [Image: source: /a.png] and fix it"
        #expect(
            TranscriptParser.sanitizeUserPromptText(text)
                == "Look at \(Self.singleImageMarker) and fix it"
        )
    }

    @Test("sanitizeUserPromptText collapses multiple image reference blocks into one counted marker")
    func sanitizeMultipleImages() {
        let suffix = " Compare these two"
        let result = TranscriptParser.sanitizeUserPromptText(
            "[Image: source: /a.png] [Image: source: /b.png]\(suffix)")
        let marker = String((result ?? "").dropLast(suffix.count))
        #expect(result?.hasSuffix(suffix) == true)
        #expect(marker.hasPrefix("[") && marker.hasSuffix("]"))
        // Two blocks collapse into a single marker that carries the count.
        #expect(marker.contains("2"))
        #expect(marker != Self.singleImageMarker)
    }

    @Test("sanitizeUserPromptText returns unmodified text when no image reference is present")
    func sanitizeNoImage() {
        #expect(TranscriptParser.sanitizeUserPromptText("Fix the auth bug") == "Fix the auth bug")
    }

    @Test("sanitizeUserPromptText returns nil for slash commands")
    func sanitizeSlashCommand() {
        #expect(TranscriptParser.sanitizeUserPromptText("/compact") == nil)
    }
}
