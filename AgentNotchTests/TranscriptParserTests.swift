import Foundation
import Testing
@testable import AgentNotchCore

@Suite("TranscriptParser Tests")
struct TranscriptParserTests {
    @Test("Parses cumulative token usage from JSONL transcript")
    func parseCumulativeUsage() throws {
        let lines = [
            #"{"type":"assistant","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":5}}"#,
            #"{"type":"assistant","usage":{"input_tokens":200,"output_tokens":80,"cache_creation_input_tokens":0,"cache_read_input_tokens":20}}"#,
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
            #"{"type":"assistant","usage":{"input_tokens":50,"output_tokens":25}}"#,
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
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add tests"}]},"sessionId":"s1"}"#,
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

    // MARK: - sanitizeUserPromptText

    @Test("sanitizeUserPromptText returns unmodified text when no image reference is present")
    func sanitizeNoImage() {
        #expect(TranscriptParser.sanitizeUserPromptText("Fix the auth bug") == "Fix the auth bug")
    }

    @Test("sanitizeUserPromptText returns nil for slash commands")
    func sanitizeSlashCommand() {
        #expect(TranscriptParser.sanitizeUserPromptText("/compact") == nil)
    }
}
