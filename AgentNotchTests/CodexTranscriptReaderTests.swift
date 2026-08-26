import Foundation
import Testing

@testable import AgentNotchCore

/// Verifies that Codex rollout transcripts normalize into the existing timeline and
/// token models.
///
/// The fixtures are minimized versions of the real line structure in
/// `~/.codex/sessions/**/rollout-*.jsonl`
/// (`{"timestamp":..., "type":..., "payload":{...}}`).
@Suite("CodexTranscriptReader Tests")
struct CodexTranscriptReaderTests {
    /// Writes an array of lines to a temporary file and deletes it afterwards.
    private func withRollout<T>(_ lines: [String], _ body: (String) throws -> T) rethrows -> T {
        let path = NSTemporaryDirectory() + "rollout-test-\(UUID().uuidString).jsonl"
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try body(path)
    }

    private func line(_ payload: String, type: String = "response_item") -> String {
        #"{"timestamp":"2026-07-27T04:00:00.000Z","type":"\#(type)","payload":\#(payload)}"#
    }

    private let sessionMeta =
        #"{"timestamp":"2026-07-27T04:00:00.000Z","type":"session_meta","payload":{"session_id":"t1","cwd":"/tmp"}}"#

    // MARK: - Format detection

    @Test("Rollout format is detected from the first line without misreading Claude transcripts")
    func detectsRolloutFormat() {
        withRollout([sessionMeta]) { path in
            #expect(CodexTranscriptReader.isRollout(path: path))
        }
        // A Claude-format transcript.
        withRollout([#"{"type":"user","message":{"role":"user","content":"Hello"},"uuid":"u1"}"#]) { path in
            #expect(!CodexTranscriptReader.isRollout(path: path))
        }
        // Detection still works when a huge session_meta truncates the line at the first 4KB.
        let hugeMeta = sessionMeta.replacingOccurrences(
            of: #""cwd":"/tmp""#,
            with: #""base_instructions":"\#(String(repeating: "x", count: 8000))""#
        )
        withRollout([hugeMeta]) { path in
            #expect(CodexTranscriptReader.isRollout(path: path))
        }
    }

    @Test("Subagent rollouts are distinguished from root rollouts by session_meta source")
    func detectsSubagentRollout() {
        let subagentMeta =
            #"{"timestamp":"2026-07-27T04:00:00.000Z","type":"session_meta","payload":{"id":"child","source":{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}},"base_instructions":"..."}}"#
        withRollout([subagentMeta]) { path in
            #expect(CodexTranscriptReader.isSubagentRollout(path: path))
        }

        // Merely mentioning "subagent" elsewhere in a root session_meta is not enough.
        let rootMeta =
            #"{"timestamp":"2026-07-27T04:00:00.000Z","type":"session_meta","payload":{"id":"root","source":"cli","base_instructions":"You may use a subagent."}}"#
        withRollout([rootMeta]) { path in
            #expect(!CodexTranscriptReader.isSubagentRollout(path: path))
        }
    }

    // MARK: - Timeline

    @Test("Picks up user and assistant turns while dropping developer and injected blocks")
    func readsMessagesAndFiltersInjected() {
        let lines = [
            sessionMeta,
            line(
                #"{"type":"message","role":"developer","content":[{"type":"input_text","text":"<permissions instructions>..."}]}"#
            ),
            line(
                ##"{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\n..."},{"type":"input_text","text":"<environment_context>\n<cwd>/tmp</cwd>"},{"type":"input_text","text":"Fix the tests"}]}"##
            ),
            line(#"{"type":"reasoning","summary":[]}"#),
            line(
                #"{"type":"message","role":"assistant","content":[{"type":"output_text","text":"On it."}]}"#),
        ]
        withRollout(lines) { path in
            let entries = CodexTranscriptReader.readTimeline(path: path)
            guard entries.count == 2,
                case .message(let user) = entries[0],
                case .message(let assistant) = entries[1]
            else {
                Issue.record("Expected [user, assistant], got \(entries.count) entries")
                return
            }
            #expect(user.role == .user)
            #expect(user.textContent == "Fix the tests")
            #expect(assistant.role == .assistant)
            #expect(assistant.textContent == "On it.")
        }
    }

    @Test("Pairs function_call with its output by call_id and reads it as a command")
    func pairsFunctionCallsByCallId() {
        let lines = [
            sessionMeta,
            line(
                #"{"type":"function_call","id":"fc_9999","name":"exec_command","arguments":"{\"cmd\":\"swift test\"}","call_id":"call_1"}"#
            ),
            line(
                #"{"type":"function_call_output","call_id":"call_1","output":"Exit code: 0\nAll tests passed"}"#
            ),
        ]
        withRollout(lines) { path in
            let entries = CodexTranscriptReader.readTimeline(path: path)
            guard entries.count == 1, case .tool(let tool) = entries[0] else {
                Issue.record("Expected 1 tool entry")
                return
            }
            #expect(tool.name == "exec_command")
            #expect(tool.kind == .command)
            #expect(tool.command == "swift test")
            #expect(tool.output == "Exit code: 0\nAll tests passed")
            #expect(!tool.isError)
        }
    }

    @Test("Recovers an unresolved request_user_input and clears it after function_call_output")
    func recoversPendingUserInput() throws {
        let request = line(
            ##"{"type":"function_call","id":"fc_question","name":"request_user_input","arguments":"{\"questions\":[{\"id\":\"target\",\"header\":\"Target\",\"question\":\"Where?\",\"options\":[{\"label\":\"Staging\",\"description\":\"Internal\"}]}],\"autoResolutionMs\":60000}","call_id":"call_question","internal_chat_message_metadata_passthrough":{"turn_id":"turn-1"}}"##
        )
        let unresolved = CodexTranscriptReader.pendingUserInputQuestions(
            in: [sessionMeta, request]
        )
        let question = try #require(unresolved.first)
        #expect(question.callId == "call_question")
        #expect(question.turnId == "turn-1")
        #expect(question.autoResolutionMs == 60_000)
        #expect(question.questions.first?.responseKey == "target")

        let resolved = CodexTranscriptReader.pendingUserInputQuestions(
            in: [
                sessionMeta,
                request,
                line(
                    #"{"type":"function_call_output","call_id":"call_question","output":"{\"answers\":{\"target\":{\"answers\":[\"Staging\"]}}}"}"#
                ),
            ]
        )
        #expect(resolved.isEmpty)
    }

    @Test("Codex exec custom calls expose their nested commands while collapsed")
    func parsesExecCustomToolCommands() throws {
        let input = """
            const test = await tools.exec_command({"cmd":"swift test","workdir":"/tmp/project"});
            const build = await tools.exec_command({"cmd":"swift build","workdir":"/tmp/project"});
            text(test.output);
            text(build.output);
            """
        let payload: [String: Any] = [
            "type": "custom_tool_call",
            "name": "exec",
            "input": input,
            "call_id": "call_exec",
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadJSON = try #require(String(data: payloadData, encoding: .utf8))
        let lines = [
            sessionMeta,
            line(payloadJSON),
            line(
                #"{"type":"custom_tool_call_output","call_id":"call_exec","output":[{"type":"input_text","text":"Tests passed"},{"type":"input_text","text":"Build complete"}]}"#
            ),
        ]

        withRollout(lines) { path in
            let entries = CodexTranscriptReader.readTimeline(path: path)
            guard entries.count == 1, case .tool(let tool) = entries[0] else {
                Issue.record("Expected 1 exec tool entry")
                return
            }
            #expect(tool.kind == .command)
            #expect(tool.command == "swift test · swift build")
            #expect(tool.inputSummary != "exec")
            #expect(tool.output == "Tests passed\nBuild complete")
        }
    }

    @Test("A non-zero exit code is an error; a missing output means still running (output=nil)")
    func detectsErrorsAndRunningCalls() {
        let lines = [
            sessionMeta,
            line(
                #"{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"false\"}","call_id":"call_err"}"#
            ),
            line(
                #"{"type":"function_call_output","call_id":"call_err","output":"Process exited with code 1\nOutput:\nboom"}"#
            ),
            line(
                #"{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"sleep 100\"}","call_id":"call_running"}"#
            ),
        ]
        withRollout(lines) { path in
            let entries = CodexTranscriptReader.readTimeline(path: path)
            guard entries.count == 2,
                case .tool(let failed) = entries[0],
                case .tool(let running) = entries[1]
            else {
                Issue.record("Expected 2 tool entries")
                return
            }
            #expect(failed.isError)
            #expect(running.output == nil)
            #expect(!running.isError)
        }
    }

    @Test("apply_patch exposes the target file and added/removed lines as a diff")
    func parsesApplyPatchAsDiff() {
        let patch =
            #"*** Begin Patch\n*** Update File: Sources/App/main.swift\n-let x = 1\n+let x = 2\n+let y = 3\n*** End Patch"#
        let lines = [
            sessionMeta,
            line(#"{"type":"custom_tool_call","name":"apply_patch","input":"\#(patch)","call_id":"call_p"}"#),
            line(#"{"type":"custom_tool_call_output","call_id":"call_p","output":"Exit code: 0\nSuccess."}"#),
        ]
        withRollout(lines) { path in
            let entries = CodexTranscriptReader.readTimeline(path: path)
            guard entries.count == 1, case .tool(let tool) = entries[0] else {
                Issue.record("Expected 1 tool entry")
                return
            }
            #expect(tool.kind == .diff)
            #expect(tool.inputSummary == "main.swift")
            #expect(tool.removedLines == ["let x = 1"])
            #expect(tool.addedLines == ["let x = 2", "let y = 3"])
            #expect(tool.diff?.files.first?.path == "Sources/App/main.swift")
        }
    }

    @Test("apply_patch preserves multiple files, context, and transcript order")
    func preservesStructuredApplyPatch() throws {
        let patch =
            #"*** Begin Patch\n*** Update File: Sources/App/main.swift\n@@\n let before = true\n-let x = 1\n+let x = 2\n*** Add File: web/app.ts\n+const ready = true\n*** End Patch"#
        let lines = [
            sessionMeta,
            line(
                #"{"type":"custom_tool_call","name":"apply_patch","input":"\#(patch)","call_id":"call_multi"}"#
            ),
        ]

        try withRollout(lines) { path in
            let entries = CodexTranscriptReader.readTimeline(path: path)
            guard entries.count == 1, case .tool(let tool) = entries[0] else {
                Issue.record("Expected 1 tool entry")
                return
            }
            let diff = try #require(tool.diff)
            #expect(diff.files.map(\.path) == ["Sources/App/main.swift", "web/app.ts"])
            #expect(
                diff.files[0].lines == [
                    ToolDiffLine(kind: .context, text: "let before = true"),
                    ToolDiffLine(kind: .removed, text: "let x = 1"),
                    ToolDiffLine(kind: .added, text: "let x = 2"),
                ])
            #expect(
                diff.files[1].lines == [
                    ToolDiffLine(kind: .added, text: "const ready = true")
                ])
        }
    }

    @Test("TranscriptReader.readTimeline routes rollout transcripts automatically")
    func routerDispatchesRollout() {
        let lines = [
            sessionMeta,
            line(#"{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}"#),
        ]
        withRollout(lines) { path in
            let entries = TranscriptReader.readTimeline(path: path)
            #expect(entries.count == 1)
        }
    }

    // MARK: - Tokens

    @Test("Cumulative tokens use the last token_count and split cached out of input")
    func parsesCumulativeUsage() {
        let tokenCount: (Int, Int, Int) -> String = { input, cached, output in
            self.line(
                #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"total_tokens":\#(input + output)}}}"#,
                type: "event_msg"
            )
        }
        let lines = [
            sessionMeta,
            tokenCount(1000, 400, 50),
            tokenCount(18777, 4992, 523),
        ]
        withRollout(lines) { path in
            let usage = TranscriptParser.parseCumulativeUsage(at: path)
            // input_tokens includes cached, so net input = 18777 - 4992.
            #expect(usage.inputTokens == 13785)
            #expect(usage.cacheReadTokens == 4992)
            #expect(usage.outputTokens == 523)
            #expect(usage.cachedTokens == 4992)
        }
    }
}
