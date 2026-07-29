import Foundation
import Testing

@testable import AgentNotchCore

/// Tests the transform that folds consecutive runs of the same tool into one row.
///
/// Five consecutive Reads taking five rows would push the surrounding messages off
/// screen and hide the flow of the conversation. Folding on the wrong boundary would
/// mix in a different tool, so these tests pin the boundaries down.
@Suite("Timeline Row Grouping Tests")
struct TimelineRowTests {
    private func tool(_ id: String, _ name: String) -> TranscriptEntry {
        .tool(
            ToolLogEntry(
                id: id, name: name, timestamp: nil, inputSummary: "",
                output: "", isError: false, kind: .text
            )
        )
    }

    private func message(_ id: String) -> TranscriptEntry {
        .message(ChatEntry(id: id, role: .user, textContent: "hi", toolUses: [], timestamp: nil))
    }

    /// Renders the folded result as a sequence of `NAME×count` (messages become `MSG`).
    private func shape(_ rows: [TimelineRow]) -> [String] {
        rows.map { row in
            switch row {
            case .message: "MSG"
            case .toolRun(let entries): "\(entries[0].name)×\(entries.count)"
            }
        }
    }

    @Test("Consecutive runs of the same tool fold into one row")
    func groupsConsecutiveSameTool() {
        let rows = TimelineRow.rows(from: [
            tool("1", "Bash"), tool("2", "Bash"), tool("3", "Bash"),
        ])
        #expect(shape(rows) == ["Bash×3"])
    }

    /// BASH BASH READ READ becomes two rows: the run breaks where the name changes.
    @Test("A run breaks where the tool name changes")
    func splitsWhenToolNameChanges() {
        let rows = TimelineRow.rows(from: [
            tool("1", "Bash"), tool("2", "Bash"),
            tool("3", "Read"), tool("4", "Read"),
        ])
        #expect(shape(rows) == ["Bash×2", "Read×2"])
    }

    /// A message in between breaks the run: same tool, but a new context.
    @Test("A message in between prevents folding")
    func doesNotGroupAcrossMessages() {
        let rows = TimelineRow.rows(from: [
            tool("1", "Read"), message("m1"), tool("2", "Read"),
        ])
        #expect(shape(rows) == ["Read×1", "MSG", "Read×1"])
    }

    @Test("A lone tool still comes back as a single run")
    func singleToolIsRunOfOne() {
        let rows = TimelineRow.rows(from: [tool("1", "Grep")])
        #expect(shape(rows) == ["Grep×1"])
    }

    @Test("Empty input returns empty output")
    func emptyInput() {
        #expect(TimelineRow.rows(from: []).isEmpty)
    }

    /// A row's id comes from the first entry in the run, so appending more executions
    /// keeps the id stable and neither scroll position nor expansion state jumps.
    @Test("A run's id comes from its first execution")
    func idIsStableWhenRunGrows() {
        let before = TimelineRow.rows(from: [tool("1", "Bash"), tool("2", "Bash")])
        let after = TimelineRow.rows(from: [tool("1", "Bash"), tool("2", "Bash"), tool("3", "Bash")])
        #expect(before[0].id == after[0].id)
        #expect(before[0].id == "tool-1")
    }

    @Test("Messages are never folded and stay in order")
    func messagesArePassedThrough() {
        let rows = TimelineRow.rows(from: [message("m1"), message("m2")])
        #expect(shape(rows) == ["MSG", "MSG"])
        #expect(rows[0].id == "msg-m1")
    }
}
