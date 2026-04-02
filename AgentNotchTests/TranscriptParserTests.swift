import Foundation
import Testing
@testable import AgentNotch

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
}
