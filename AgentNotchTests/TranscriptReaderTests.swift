import Foundation
import Testing
@testable import AgentNotchCore

@Suite("TranscriptReader")
struct TranscriptReaderTests {
    @Test("Parses user message")
    func parsesUser() throws {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"Hello world"},"timestamp":"2026-04-03T12:00:00.000Z","sessionId":"s1","uuid":"u1"}
        """
        let path = tmpFile(jsonl)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = TranscriptReader.read(path: path, tail: 100)
        #expect(entries.count == 1)
        #expect(entries[0].role == .user)
        #expect(entries[0].textContent == "Hello world")
    }

    @Test("Parses assistant text")
    func parsesAssistantText() throws {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}]},"uuid":"a1"}
        """
        let path = tmpFile(jsonl)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = TranscriptReader.read(path: path, tail: 100)
        #expect(entries.count == 1)
        #expect(entries[0].role == .assistant)
        #expect(entries[0].textContent == "Hi there!")
    }

    @Test("Parses assistant tool_use")
    func parsesToolUse() throws {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/src/main.swift"}}]},"uuid":"a2"}
        """
        let path = tmpFile(jsonl)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = TranscriptReader.read(path: path, tail: 100)
        #expect(entries.count == 1)
        #expect(entries[0].toolUses.count == 1)
        #expect(entries[0].toolUses[0].name == "Edit")
    }

    @Test("Skips non-message lines")
    func skipsNonMessage() throws {
        let jsonl = """
        {"type":"file-history-snapshot","snapshot":{}}
        {"type":"system","subtype":"stop_hook_summary"}
        {"type":"user","message":{"role":"user","content":"test"},"uuid":"u2"}
        """
        let path = tmpFile(jsonl)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = TranscriptReader.read(path: path, tail: 100)
        #expect(entries.count == 1)
    }

    @Test("Tail limits from end")
    func tailLimits() throws {
        var lines: [String] = []
        for i in 0..<20 {
            lines.append("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"msg \(i)\"},\"uuid\":\"u\(i)\"}")
        }
        let path = tmpFile(lines.joined(separator: "\n"))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = TranscriptReader.read(path: path, tail: 5)
        #expect(entries.count == 5)
        #expect(entries[0].textContent == "msg 15")
    }

    private func tmpFile(_ content: String) -> String {
        let path = NSTemporaryDirectory() + "test-\(UUID()).jsonl"
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
