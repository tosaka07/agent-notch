import Foundation
import Testing
@testable import AgentNotchCore

@Suite("TranscriptParser Tests")
struct TranscriptParserTests {
    /// usage は `message.usage` にネストしている（実データで確認済み。top-level `usage` は存在しない）。
    /// 以前のテストは top-level を前提にしていたため、常に 0 を返すバグを検出できていなかった。
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

    /// 1 つの assistant メッセージが content block ごとに複数行へ分割される
    /// （同じ `message.id` / `requestId` で thinking / text / tool_use が別行）。
    /// 単純合算すると 2〜3 倍になるため、最後の行だけを採用する。
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

    // MARK: - sanitizeUserPromptText (画像参照マーカーの整形)

    @Test("sanitizeUserPromptText replaces a single image reference block with [画像]")
    func sanitizeSingleImageOnly() {
        let text = "[Image: source: /Users/dev/.claude/image-cache/abc.png]"
        #expect(TranscriptParser.sanitizeUserPromptText(text) == "[画像]")
    }

    @Test("sanitizeUserPromptText keeps surrounding text and replaces image block with [画像]")
    func sanitizeImageMixedWithText() {
        let text = "この画像を見て [Image: source: /Users/dev/.claude/image-cache/abc.png] 直してください"
        #expect(
            TranscriptParser.sanitizeUserPromptText(text)
                == "この画像を見て [画像] 直してください"
        )
    }

    @Test("sanitizeUserPromptText collapses multiple image reference blocks into [画像×N]")
    func sanitizeMultipleImages() {
        let text = "[Image: source: /a.png] [Image: source: /b.png] この2枚を比較して"
        #expect(
            TranscriptParser.sanitizeUserPromptText(text)
                == "[画像×2] この2枚を比較して"
        )
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
