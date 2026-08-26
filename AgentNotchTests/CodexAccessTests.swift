import Foundation
import Testing

@testable import AgentNotchCore

/// The Codex integration switch has to close **every** door Codex data comes through, not only the
/// one that happened to be noticed. These pin each reader to `CodexAccess`.
///
/// The gate is process-wide state, so the suite is serialized and each test restores it.
@Suite("Codex access gate", .serialized)
struct CodexAccessTests {
    /// Restores the permissive default however a test ends.
    private func withCodexAccess(_ allowed: Bool, _ body: () throws -> Void) rethrows {
        CodexAccess.setAllowed(allowed)
        defer { CodexAccess.setAllowed(true) }
        try body()
    }

    @Test("Codex-owned paths are recognized from the directory, not the file's contents")
    func codexOwnershipIsDecidedByPath() {
        #expect(CodexAccess.isCodexOwned(path: "/Users/x/.codex/sessions/2026/07/rollout-a.jsonl"))
        #expect(!CodexAccess.isCodexOwned(path: "/Users/x/.claude/projects/p/session.jsonl"))
    }

    @Test("While off, a Claude transcript is still readable and a Codex one is not")
    func transcriptGateAppliesOnlyToCodex() {
        withCodexAccess(false) {
            #expect(!CodexAccess.allowsTranscript(at: "/Users/x/.codex/sessions/rollout-a.jsonl"))
            #expect(CodexAccess.allowsTranscript(at: "/Users/x/.claude/projects/p/s.jsonl"))
        }
        withCodexAccess(true) {
            #expect(CodexAccess.allowsTranscript(at: "/Users/x/.codex/sessions/rollout-a.jsonl"))
        }
    }

    @Test("A rollout transcript is not opened while the integration is off")
    func transcriptReadersHonourTheGate() throws {
        let home = try makeCodexRollout()
        defer { try? FileManager.default.removeItem(at: home.directory) }

        // On: the fixture parses, which is what makes the "off" assertions below meaningful.
        #expect(!TranscriptReader.readTimeline(path: home.rollout).isEmpty)
        #expect(TranscriptParser.parseCumulativeUsage(at: home.rollout).outputTokens > 0)

        withCodexAccess(false) {
            #expect(TranscriptReader.readTimeline(path: home.rollout).isEmpty)
            #expect(TranscriptParser.parseCumulativeUsage(at: home.rollout).outputTokens == 0)
            #expect(TranscriptParser.sessionTitle(at: home.rollout) == nil)
            #expect(TranscriptParser.lastAssistantMessage(at: home.rollout) == nil)
            #expect(TranscriptParser.userMessages(at: home.rollout) == (nil, nil))
        }
    }

    @Test("The daily cost scan returns an empty report while the integration is off")
    func dailyCostHonoursTheGate() throws {
        let home = try makeCodexRollout()
        defer { try? FileManager.default.removeItem(at: home.directory) }

        let enabled = DailyCostAggregator.codexReport(sessionsDirectory: home.sessionsDirectory)
        #expect(!enabled.days.isEmpty)

        withCodexAccess(false) {
            let disabled = DailyCostAggregator.codexReport(sessionsDirectory: home.sessionsDirectory)
            #expect(disabled.days.isEmpty)
            #expect(disabled.unsupportedModels.isEmpty)
        }
    }

    @Test("Usage returns nothing while the integration is off, without calling either route")
    func usageHonoursTheGate() async {
        // Both routes are Codex's own — its app server and its rollout files — so neither may run.
        // `.shared` reaches the real app server, so this asserts on the gate's own decision.
        CodexAccess.setAllowed(false)
        defer { CodexAccess.setAllowed(true) }

        #expect(await CodexUsageClient.shared.fetchUsage() == nil)
    }

    // MARK: - Fixture

    private struct Fixture {
        let directory: URL
        let sessionsDirectory: String
        let rollout: String
    }

    /// A minimal Codex rollout: one user turn, one assistant turn, one `token_count`.
    private func makeCodexRollout() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-codex-access-\(UUID().uuidString)")
        let sessions = directory.appendingPathComponent(".codex/sessions/2026/07/27")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appendingPathComponent("rollout-2026-07-27T10-00-00-abc.jsonl")

        let lines = [
            #"{"timestamp":"2026-07-27T10:00:00.000Z","type":"session_meta","payload":{"id":"abc","cwd":"/tmp","originator":"codex_cli_rs","instructions":null}}"#,
            #"{"timestamp":"2026-07-27T10:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello codex"}]}}"#,
            #"{"timestamp":"2026-07-27T10:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello back"}]}}"#,
            #"{"timestamp":"2026-07-27T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5.1-codex","total_token_usage":{"input_tokens":1200,"cached_input_tokens":0,"output_tokens":340,"reasoning_output_tokens":0,"total_tokens":1540}}}}"#,
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        return Fixture(
            directory: directory,
            sessionsDirectory: directory.appendingPathComponent(".codex/sessions").path,
            rollout: rollout.path
        )
    }
}
