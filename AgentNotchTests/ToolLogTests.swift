import Foundation
import Testing

@testable import AgentNotchCore

/// LOG タブ用のツールログ読み取りをテストする。
///
/// transcript の `tool_use` と `tool_result` は別のメッセージに分かれて出るため、
/// `tool_use_id` での対応付けが要。形式（結果が文字列 / ブロック配列）も両方来る。
@Suite("TranscriptReader.readToolLog Tests")
struct ToolLogTests {
    private func withTempTranscript(_ lines: [String], _ body: (String) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-log-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }
        try body(path.path)
    }

    @Test("tool_use と tool_result を tool_use_id で対応付ける")
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

    /// `tool_result.content` は文字列だけでなく `[{type:"text", text:...}]` でも来る。
    @Test("ブロック配列形式の tool_result も読める")
    func readsBlockArrayResult() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_2","name":"Grep","input":{"pattern":"DSColors"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_2","content":[{"type":"text","text":"DSColors.swift\nDSSpacing.swift"}]}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.kind == .table)
            #expect(entry.output == "DSColors.swift\nDSSpacing.swift")
            #expect(entry.resultSummary == "2 lines")
        }
    }

    /// Edit は old_string / new_string から差分行を組み立てる。
    @Test("Edit は差分行を組み立て、増減を要約に出す")
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
        }
    }

    /// 結果がまだ来ていないツール（実行中）は output が nil のまま返る。
    @Test("結果待ちのツールは output が nil で返る")
    func keepsRunningToolWithoutResult() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_4","name":"Bash","input":{"command":"sleep 30"}}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.output == nil)
            #expect(entry.command == "sleep 30")
        }
    }

    @Test("エラー結果は isError と要約に反映される")
    func marksErrorResult() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_5","name":"Bash","input":{"command":"false"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_5","content":"command failed","is_error":true}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let entry = try #require(TranscriptReader.readToolLog(path: path).first)
            #expect(entry.isError)
            #expect(entry.resultSummary == "error")
        }
    }

    /// tail は「最後の N 件」を実行順で返す。
    @Test("tail は実行順で最後の N 件を返す")
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

    @Test("ツール名から出力の見せ方を決める")
    func mapsToolNameToKind() {
        #expect(ToolLogEntry.kind(forToolNamed: "Bash") == .command)
        #expect(ToolLogEntry.kind(forToolNamed: "Grep") == .table)
        #expect(ToolLogEntry.kind(forToolNamed: "Write") == .diff)
        #expect(ToolLogEntry.kind(forToolNamed: "WebFetch") == .text)
    }
}

/// チャットとツールを 1 本のタイムラインに混ぜる読み取りのテスト。
@Suite("TranscriptReader.readTimeline Tests")
struct TimelineTests {
    private func withTempTranscript(_ lines: [String], _ body: (String) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }
        try body(path.path)
    }

    /// テキストとツールが時系列で交互に並ぶ。
    @Test("メッセージとツールを timestamp 順に混ぜる")
    func interleavesByTimestamp() throws {
        let lines = [
            #"{"type":"user","timestamp":"2026-07-25T12:00:00.000Z","uuid":"u1","message":{"content":[{"type":"text","text":"ビルドして"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:01.000Z","uuid":"a1","message":{"content":[{"type":"text","text":"実行します"},{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"swift build"}}]}}"#,
            #"{"type":"user","timestamp":"2026-07-25T12:00:05.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"Build complete!"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:06.000Z","uuid":"a2","message":{"content":[{"type":"text","text":"通りました"}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let timeline = TranscriptReader.readTimeline(path: path)
            let kinds = timeline.map { item -> String in
                switch item {
                case .message(let entry): "msg:\(entry.textContent)"
                case .tool(let entry): "tool:\(entry.name)"
                }
            }
            #expect(kinds == ["msg:ビルドして", "msg:実行します", "tool:Bash", "msg:通りました"])
        }
    }

    /// assistant の text と tool_use は同じ行に同居する。タイムラインではツールを
    /// 独立エントリにするので、message 側に tool_use を含めると二重表示になる。
    @Test("メッセージ側に tool_use を含めない（二重表示を防ぐ）")
    func doesNotDuplicateToolUses() throws {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:01.000Z","uuid":"a1","message":{"content":[{"type":"text","text":"やります"},{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"ls"}}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let timeline = TranscriptReader.readTimeline(path: path)
            #expect(timeline.count == 2)
            guard case .message(let message) = timeline[0] else {
                Issue.record("先頭は message のはず")
                return
            }
            #expect(message.toolUses.isEmpty)
            guard case .tool = timeline[1] else {
                Issue.record("2 番目は tool のはず")
                return
            }
        }
    }

    /// テキストが空で tool_use だけの assistant 行は message として出さない。
    @Test("tool_use だけの行は message を作らない")
    func skipsToolOnlyMessages() throws {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-07-25T12:00:01.000Z","uuid":"a1","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"/a/b.swift"}}]}}"#,
        ]
        try withTempTranscript(lines) { path in
            let timeline = TranscriptReader.readTimeline(path: path)
            #expect(timeline.count == 1)
            guard case .tool = timeline[0] else {
                Issue.record("tool だけが残るはず")
                return
            }
        }
    }
}
