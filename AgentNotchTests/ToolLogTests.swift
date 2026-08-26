import Foundation
import Testing

@testable import AgentNotchCore

/// Tests the tool-log reader behind the LOG tab.
///
/// A transcript emits `tool_use` and `tool_result` in separate messages, so pairing
/// them by `tool_use_id` is essential. Results arrive both as plain strings and as
/// block arrays.
@Suite("TranscriptReader.readToolLog Tests")
struct ToolLogTests {
    private func withTempTranscript(_ lines: [String], _ body: (String) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-log-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }
        try body(path.path)
    }

    @Test("Pairs tool_use with tool_result by tool_use_id")
    func pairsUseAndResult() throws {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:00.000Z","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"pnpm build"}}]}}"#,
            #"{"type":"user","timestamp":"2026-07-25T12:00:04.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"tasks: 12 successful","is_error":false}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let log = TranscriptReader.readToolLog(path: path)
            #expect(log.count == 1)
            let entry = try #require(log.first)
            #expect(entry.name == "Bash")
            #expect(entry.command == "pnpm build")
            #expect(entry.output == "tasks: 12 successful")
            #expect(entry.isError == false)
            #expect(entry.kind == .command)
        }
    }

    /// `tool_result.content` may be a string or a `[{type:"text", text:...}]` array.
    @Test("Reads tool_result in block-array form")
    func readsBlockArrayResult() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_2","name":"Grep","input":{"pattern":"DSColors"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_2","content":[{"type":"text","text":"DSColors.swift\nDSSpacing.swift"}]}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.kind == .table)
            #expect(entry.output == "DSColors.swift\nDSSpacing.swift")
            // Build the expectation through the same localization path so the test
            // does not depend on the machine's language.
            #expect(entry.resultSummary == AppLocalization.localized("\(2) lines"))
        }
    }

    /// Edit builds diff lines from old_string / new_string.
    @Test("Edit builds diff lines and reports added/removed counts in the summary")
    func buildsDiffLines() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_3","name":"Edit","input":{"file_path":"/a/DSSpacing.swift","old_string":"let md = 12","new_string":"let md = s(12)\nlet dot = 2"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_3","content":"ok"}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.kind == .diff)
            #expect(entry.removedLines == ["let md = 12"])
            #expect(entry.addedLines == ["let md = s(12)", "let dot = 2"])
            #expect(entry.resultSummary == "+2 −1")
            #expect(entry.inputSummary == "DSSpacing.swift")
            let file = try #require(entry.diff?.files.first)
            #expect(file.path == "/a/DSSpacing.swift")
            #expect(file.lines.map(\.kind) == [.removed, .added, .added])
        }
    }

    /// A tool whose result has not arrived yet (still running) keeps output nil.
    @Test("A tool awaiting its result returns output == nil")
    func keepsRunningToolWithoutResult() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_4","name":"Bash","input":{"command":"sleep 30"}}]}}"#
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.output == nil)
            #expect(entry.command == "sleep 30")
        }
    }

    @Test("An error result sets isError and shows up in the summary")
    func marksErrorResult() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_5","name":"Bash","input":{"command":"false"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_5","content":"command failed","is_error":true}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.isError)
            // Same localization path as production, so the assertion is locale-independent.
            #expect(entry.resultSummary == AppLocalization.localized("error"))
        }
    }

    /// tail returns the last N entries in execution order.
    @Test("tail returns the last N entries in execution order")
    func respectsTail() throws {
        let lines = (1...5).flatMap { index in
            [
                """
                {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_\(index)","name":"Bash","input":{"command":"echo \(index)"}}]}}
                """,
                """
                {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_\(index)","content":"\(index)"}]}}
                """,
            ]
        }
        try withTempTranscript(lines) { path in
            let log = TranscriptReader.readToolLog(path: path, tail: 2)
            #expect(log.map(\.id) == ["tu_4", "tu_5"])
        }
    }

    @Test("The tool name decides how its output is presented")
    func mapsToolNameToKind() {
        #expect(ToolLogEntry.kind(forToolNamed: "Bash") == .command)
        #expect(ToolLogEntry.kind(forToolNamed: "Grep") == .table)
        #expect(ToolLogEntry.kind(forToolNamed: "Write") == .diff)
        #expect(ToolLogEntry.kind(forToolNamed: "WebFetch") == .text)
    }
}

/// Tests the reader that merges chat and tools into a single timeline.
@Suite("TranscriptReader.readTimeline Tests")
struct TimelineTests {
    private func withTempTranscript(_ lines: [String], _ body: (String) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }
        try body(path.path)
    }

    /// Text and tools interleave in chronological order.
    @Test("Merges messages and tools by timestamp")
    func interleavesByTimestamp() throws {
        let lines = [
            #"{"type":"user","timestamp":"2026-07-25T12:00:00.000Z","uuid":"u1","message":{"content":[{"type":"text","text":"Build it"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:01.000Z","uuid":"a1","message":{"content":[{"type":"text","text":"Running it"},{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"swift build"}}]}}"#,
            #"{"type":"user","timestamp":"2026-07-25T12:00:05.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"Build complete!"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:06.000Z","uuid":"a2","message":{"content":[{"type":"text","text":"It passed"}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let timeline = TranscriptReader.readTimeline(path: path)
            let kinds = timeline.map { item -> String in
                switch item {
                case .message(let entry): "msg:\(entry.textContent)"
                case .tool(let entry): "tool:\(entry.name)"
                }
            }
            #expect(kinds == ["msg:Build it", "msg:Running it", "tool:Bash", "msg:It passed"])
        }
    }

    /// An assistant line holds both text and tool_use. The timeline renders tools as
    /// their own entries, so keeping tool_use in the message would show it twice.
    @Test("Messages exclude tool_use so nothing is rendered twice")
    func doesNotDuplicateToolUses() throws {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:01.000Z","uuid":"a1","message":{"content":[{"type":"text","text":"Sure"},{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"ls"}}]}}"#
        ]
        try withTempTranscript(lines) { path in
            let timeline = TranscriptReader.readTimeline(path: path)
            #expect(timeline.count == 2)
            guard case .message(let message) = timeline[0] else {
                Issue.record("The first entry should be a message")
                return
            }
            #expect(message.toolUses.isEmpty)
            guard case .tool = timeline[1] else {
                Issue.record("The second entry should be a tool")
                return
            }
        }
    }

    /// An assistant line with no text and only a tool_use produces no message.
    @Test("A tool_use-only line creates no message")
    func skipsToolOnlyMessages() throws {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:01.000Z","uuid":"a1","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"/a/b.swift"}}]}}"#
        ]
        try withTempTranscript(lines) { path in
            let timeline = TranscriptReader.readTimeline(path: path)
            #expect(timeline.count == 1)
            guard case .tool = timeline[0] else {
                Issue.record("Only the tool should remain")
                return
            }
        }
    }
}
