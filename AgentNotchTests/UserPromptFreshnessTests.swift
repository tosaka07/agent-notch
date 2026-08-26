import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Regression tests: a session card must never show the *previous* prompt.
///
/// There were two causes, both the same shape — **an asynchronous transcript read
/// landing after the hook and overwriting its fresher value**:
/// - `resolveFirstUserPromptIfNeeded` in `backfillSession` assigned `lastUserPrompt`
///   unconditionally
/// - the `UserPromptSubmit` fallback waited a fixed 500ms before reading the transcript
@Suite("User Prompt Freshness Tests")
@MainActor
struct UserPromptFreshnessTests {
    /// Writes a transcript containing two user messages.
    private func writeTranscript(_ messages: [String]) throws -> String {
        let path = NSTemporaryDirectory() + "notch-prompt-\(UUID().uuidString).jsonl"
        let lines = messages.map { text in
            #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// A backfill read landing after the hook delivered a newer prompt must not
    /// overwrite it with the older message. **This is the core of the bug.**
    @Test("Backfill does not overwrite the newer prompt delivered by the hook")
    func backfillDoesNotClobberLivePromptcase() async throws {
        let path = try writeTranscript([
            "Request from the previous turn", "Newer than that, but older than now",
        ])
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.transcriptPath = path

        // The hook delivered this turn's input (the normal route, prompt in the payload).
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "UserPromptSubmit",
                "session_id": sessionId,
                "prompt": "The request just sent",
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.lastUserPrompt == "The request just sent")

        // Then backfill (the asynchronous transcript read) runs and lands.
        EventProcessor.backfillSession(
            sessionId, cwd: nil, transcriptPath: path, pid: nil, tty: nil, manager: manager
        )
        try await Task.sleep(for: .milliseconds(300))

        #expect(session.lastUserPrompt == "The request just sent")
        // Meanwhile firstUserPrompt, still empty, can be filled from the transcript.
        #expect(session.firstUserPrompt == "Request from the previous turn")
    }

    /// A session that started before the app launched has no hook-supplied value, so
    /// the transcript fills it in — the backfill itself must still work.
    @Test("Falls back to the transcript when the hook supplied nothing")
    func backfillFillsWhenNothingKnown() async throws {
        let path = try writeTranscript(["First request", "Last request"])
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "s2", agentType: .claudeCode)
        session.transcriptPath = path

        EventProcessor.backfillSession(
            "s2", cwd: nil, transcriptPath: path, pid: nil, tty: nil, manager: manager
        )
        try await Task.sleep(for: .milliseconds(300))

        #expect(session.firstUserPrompt == "First request")
        #expect(session.lastUserPrompt == "Last request")
    }

    /// Waits until an in-progress append stops, so even if writing is still underway
    /// when the hook fires, the read happens after the last entry has landed.
    @Test("waitUntilSettled waits for an in-progress append to stop")
    func waitUntilSettledWaitsForOngoingWrites() async throws {
        let path = try writeTranscript(["First request"])

        // Start writing immediately and append three times at 40ms intervals, so the
        // append is genuinely in progress.
        Task.detached {
            for index in 1...3 {
                let line = #"{"type":"user","message":{"role":"user","content":"Append \#(index)"}}"#
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    handle.seekToEndOfFile()
                    handle.write(Data(("\n" + line).utf8))
                    try? handle.close()
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }

        await TranscriptParser.waitUntilSettled(at: path)
        #expect(TranscriptParser.lastUserMessage(at: path) == "Append 3")
    }

    /// **Known limitation**: it only watches for size changes, so it cannot wait for a
    /// write that has not started yet. Callers with a gap before the write — the
    /// `UserPromptSubmit` fallback — therefore need `minimumWait` to pause first.
    @Test("minimumWait absorbs the gap before a write begins")
    func minimumWaitAbsorbsDelayBeforeWriteStarts() async throws {
        let path = try writeTranscript(["First request"])

        // Without minimumWait it returns as soon as it sees the same size twice.
        // Verify that baseline before launching the delayed writer; otherwise a
        // heavily loaded parallel test run can schedule the writer first and
        // turn this timing assertion into a race.
        await TranscriptParser.waitUntilSettled(at: path)
        #expect(TranscriptParser.lastUserMessage(at: path) == "First request")

        // Nothing happens for 200ms, then the append arrives.
        Task.detached {
            try? await Task.sleep(for: .milliseconds(200))
            let line = #"{"type":"user","message":{"role":"user","content":"A request that arrived later"}}"#
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(Data(("\n" + line).utf8))
                try? handle.close()
            }
        }

        // With a pause first, the read picks up the appended entry.
        await TranscriptParser.waitUntilSettled(at: path, minimumWait: .milliseconds(300))
        #expect(TranscriptParser.lastUserMessage(at: path) == "A request that arrived later")
    }
}
