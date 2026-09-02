import AgentNotchCore
import Foundation
import Testing

@testable import AgentNotch

/// Regression tests: a PermissionRequest approved inside a subagent must stay
/// reflected on the session card.
@Suite("EventProcessor status guard tests")
@MainActor
struct EventProcessorTests {
    @Test("Stop waits for every subagent before marking the root turn done")
    func stopWaitsForRunningSubagents() {
        let manager = SessionManager()
        let sessionId = "root"

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "SubagentStart",
                "session_id": sessionId,
                "agent_type": "Explore",
                "agent_id": "agent-a",
            ]),
            agentType: .claudeCode, manager: manager
        )
        let session = manager.session(for: sessionId)!
        #expect(session.status == .subagentRunning)
        #expect(session.runningSubagentCount == 1)

        // Claude can emit Stop for an intermediate root response before the last
        // SubagentStop arrives. That is not a user-input boundary yet.
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "Stop",
                "session_id": sessionId,
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.status == .subagentRunning)
        #expect(session.runningSubagentCount == 1)
        #expect(session.doneAt == nil)

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "SubagentStop",
                "session_id": sessionId,
                "agent_type": "Explore",
                "agent_id": "agent-a",
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.status == .thinking)
        #expect(session.runningSubagentCount == 0)

        // Only the root Stop after all agents have settled represents waiting for
        // the next user input.
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "Stop",
                "session_id": sessionId,
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.status == .done)
        #expect(session.doneAt != nil)
    }

    /// Regression: a session that backgrounded a long-running command (a debug build of
    /// this app, a dev server) reported `background_tasks` on every Stop and stayed pinned
    /// to "Thinking" for hours, because nothing re-checks a deferred Stop.
    @Test("Stop completes even while a backgrounded shell command is still running")
    func stopCompletesDespiteDetachedShellTask() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "root", agentType: .claudeCode)
        session.status = .thinking

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "Stop",
                "session_id": "root",
                "background_tasks": [
                    [
                        "id": "task-1",
                        "type": "shell",
                        "status": "running",
                        "description": "Run the debug build",
                    ]
                ],
                "session_crons": [],
            ]),
            agentType: .claudeCode, manager: manager
        )

        #expect(session.status == .done)
        #expect(session.doneAt != nil)
    }

    @Test("Stop waits when Claude reports background work even if a start hook was missed")
    func stopWaitsForPayloadBackgroundTasks() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "root", agentType: .claudeCode)
        session.status = .thinking

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "Stop",
                "session_id": "root",
                "background_tasks": [
                    [
                        "id": "task-1",
                        "type": "teammate",
                        "status": "running",
                        "description": "Review the implementation",
                    ]
                ],
                "session_crons": [],
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.status == .thinking)
        #expect(session.doneAt == nil)

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "Stop",
                "session_id": "root",
                "background_tasks": [],
                "session_crons": [],
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.status == .done)
        #expect(session.doneAt != nil)
    }

    @Test("A Codex child rollout Stop never marks a user-input boundary")
    func codexChildStopDoesNotComplete() {
        let path = NSTemporaryDirectory() + "codex-child-\(UUID().uuidString).jsonl"
        let sessionMeta =
            #"{"timestamp":"2026-07-27T04:00:00.000Z","type":"session_meta","payload":{"id":"child","source":{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}}}}"#
        try? sessionMeta.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "child", agentType: .codex)
        session.status = .thinking
        session.transcriptPath = path

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "Stop",
                "session_id": "child",
                "transcript_path": path,
                "last_assistant_message": "Reported back to root.",
            ]),
            agentType: .codex, manager: manager
        )

        #expect(session.status == .idle)
        #expect(session.doneAt == nil)
    }

    @Test("TeammateIdle does not mark the root turn done")
    func teammateIdleDoesNotCompleteRootTurn() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "root", agentType: .claudeCode)
        session.status = .thinking

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "TeammateIdle",
                "session_id": "root",
                "team_name": "alpha",
                "teammate_name": "researcher",
                "teammate_session_id": "teammate-1",
            ]),
            agentType: .claudeCode, manager: manager
        )

        #expect(session.status == .thinking)
        #expect(session.doneAt == nil)
        #expect(session.teammateName == nil)
    }

    @Test("permissionWaiting survives a concurrent (different tool) PreToolUse/PostToolUse")
    func permissionWaitingSurvivesConcurrentToolEvent() {
        let manager = SessionManager()
        let sessionId = "s1"

        let subagentStart = ClaudeEventParser.parse([
            "hook_event_name": "SubagentStart",
            "session_id": sessionId,
            "agent_type": "explorer",
            "agent_id": "agent-a",
        ])
        EventProcessor.apply(subagentStart, agentType: .claudeCode, manager: manager)
        let session = manager.session(for: sessionId)!
        #expect(session.status == .subagentRunning)

        // A tool in another subagent asks for approval, moving to permissionWaiting.
        let permissionRequest = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "Bash",
            "tool_use_id": "tool-1",
            "tool_input": ["command": "rm -rf foo"],
        ])
        EventProcessor.apply(permissionRequest, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
        #expect(session.pendingPermissions.count == 1)

        // While awaiting approval, PreToolUse/PostToolUse for a different tool_use_id
        // must not clear the permissionWaiting badge.
        let otherToolStart = ClaudeEventParser.parse([
            "hook_event_name": "PreToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
            "tool_input": ["file_path": "/tmp/x"],
        ])
        EventProcessor.apply(otherToolStart, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)

        let otherToolEnd = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
        ])
        EventProcessor.apply(otherToolEnd, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
    }

    @Test("idle_prompt notification does not clear permissionWaiting")
    func idlePromptDoesNotClearPermissionWaiting() {
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: sessionId, toolName: "Bash",
                toolInput: [:], toolUseId: "tool-1", timestamp: Date(), canRespond: true
            )
        ]

        let idlePrompt = ClaudeEventParser.parse([
            "hook_event_name": "Notification",
            "session_id": sessionId,
            "type": "idle_prompt",
            "message": "",
        ])
        EventProcessor.apply(idlePrompt, agentType: .claudeCode, manager: manager)

        #expect(session.status == .permissionWaiting)
    }

    @Test("PreCompact does not clear permissionWaiting (symmetry with PostCompact)")
    func preCompactDoesNotClearPermissionWaiting() {
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: sessionId, toolName: "Bash",
                toolInput: [:], toolUseId: "tool-1", timestamp: Date(), canRespond: true
            )
        ]

        let preCompact = ClaudeEventParser.parse([
            "hook_event_name": "PreCompact",
            "session_id": sessionId,
        ])
        EventProcessor.apply(preCompact, agentType: .claudeCode, manager: manager)

        #expect(session.status == .permissionWaiting)
    }

    @Test("UserPromptSubmit does not clear permissionWaiting")
    func userPromptDoesNotClearPermissionWaiting() {
        let manager = SessionManager()
        let sessionId = "s1"
        let session = manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "p1", agentType: .claudeCode, sessionId: sessionId, toolName: "Bash",
                toolInput: [:], toolUseId: "tool-1", timestamp: Date(), canRespond: true
            )
        ]

        let userPrompt = ClaudeEventParser.parse([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "prompt": "Keep going",
        ])
        EventProcessor.apply(userPrompt, agentType: .claudeCode, manager: manager)

        #expect(session.status == .permissionWaiting)
    }

    /// Codex transcripts are not in Claude's format, so backfill cannot fill in
    /// firstUserPrompt. Both first and last must come from the UserPromptSubmit
    /// payload — the session card shows firstUserPrompt by default, so without it no
    /// prompt appears at all.
    @Test("A UserPromptSubmit payload fills both firstUserPrompt and lastUserPrompt")
    func userPromptFillsFirstAndLastPrompt() {
        let manager = SessionManager()
        let sessionId = "codex-1"

        let first = ClaudeEventParser.parse([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "prompt": "Write some tests",
        ])
        EventProcessor.apply(first, agentType: .codex, manager: manager)
        let session = manager.session(for: sessionId)!
        #expect(session.firstUserPrompt == "Write some tests")
        #expect(session.lastUserPrompt == "Write some tests")

        // From the second prompt on, only lastUserPrompt moves; firstUserPrompt is kept.
        let second = ClaudeEventParser.parse([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "prompt": "Keep going",
        ])
        EventProcessor.apply(second, agentType: .codex, manager: manager)
        #expect(session.firstUserPrompt == "Write some tests")
        #expect(session.lastUserPrompt == "Keep going")
    }

    /// Codex keeps its PermissionRequest hook open and accepts allow/deny on stdout,
    /// so the notch can answer it. Agents without that response contract remain observe-only.
    @Test("A Codex PermissionRequest is answerable while unsupported agents stay observe-only")
    func codexPermissionCanRespond() {
        let manager = SessionManager()
        let codexEvent = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": "codex-1",
            "tool_name": "shell",
            "tool_input": ["command": "rm -rf build"],
        ])

        EventProcessor.apply(codexEvent, agentType: .codex, manager: manager)
        let codexSession = manager.session(for: "codex-1")!
        #expect(codexSession.status == .permissionWaiting)
        #expect(codexSession.pendingPermissions.first?.canRespond == true)

        let geminiEvent = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": "gemini-1",
            "tool_name": "shell",
            "tool_input": ["command": "rm -rf build"],
        ])
        EventProcessor.apply(geminiEvent, agentType: .geminiCLI, manager: manager)
        #expect(manager.session(for: "gemini-1")?.pendingPermissions.first?.canRespond == false)
    }

    @Test("permissionWaiting from a pending AskUserQuestion also survives a concurrent tool event")
    func pendingQuestionSurvivesConcurrentToolEvent() {
        let manager = SessionManager()
        let sessionId = "s1"

        let subagentStart = ClaudeEventParser.parse([
            "hook_event_name": "SubagentStart",
            "session_id": sessionId,
            "agent_type": "explorer",
            "agent_id": "agent-a",
        ])
        EventProcessor.apply(subagentStart, agentType: .claudeCode, manager: manager)
        let session = manager.session(for: sessionId)!
        #expect(session.status == .subagentRunning)

        // Another subagent moves to awaiting-answer via AskUserQuestion (a PermissionRequest).
        let askQuestion = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "AskUserQuestion",
            "tool_use_id": "tool-q1",
            "tool_input": [
                "questions": [
                    [
                        "question": "Which approach should we take?",
                        "options": [["label": "A"], ["label": "B"]],
                    ]
                ]
            ],
        ])
        EventProcessor.apply(askQuestion, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
        #expect(session.pendingQuestion != nil)

        // While awaiting an answer, PreToolUse/PostToolUse from another subagent must
        // not clear the badge.
        let otherToolStart = ClaudeEventParser.parse([
            "hook_event_name": "PreToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
            "tool_input": ["file_path": "/tmp/x"],
        ])
        EventProcessor.apply(otherToolStart, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)

        let otherToolEnd = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": sessionId,
            "tool_name": "Read",
            "tool_use_id": "tool-2",
        ])
        EventProcessor.apply(otherToolEnd, agentType: .claudeCode, manager: manager)
        #expect(session.status == .permissionWaiting)
    }

    @Test("Separate Claude questions and permissions append without replacing the visible card")
    func interruptionsShareArrivalOrder() {
        let manager = SessionManager()
        let sessionId = "queued"
        manager.setMuted(sessionId, true)

        func question(_ id: String, _ text: String) -> ClaudeEvent {
            ClaudeEventParser.parse([
                "hook_event_name": "PreToolUse",
                "session_id": sessionId,
                "tool_name": "AskUserQuestion",
                "tool_use_id": id,
                "tool_input": [
                    "questions": [
                        [
                            "question": text,
                            "options": [["label": "Yes"], ["label": "No"]],
                        ]
                    ]
                ],
            ])
        }

        EventProcessor.apply(
            question("question-1", "First?"),
            agentType: .claudeCode,
            manager: manager
        )
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PermissionRequest",
                "session_id": sessionId,
                "tool_name": "Bash",
                "tool_use_id": "permission-1",
                "tool_input": ["command": "make test"],
            ]),
            agentType: .claudeCode,
            manager: manager
        )
        EventProcessor.apply(
            question("question-2", "Third?"),
            agentType: .claudeCode,
            manager: manager
        )

        let session = manager.session(for: sessionId)
        #expect(
            session?.pendingInterruptions.items.map(\.id)
                == ["question:question-1", "permission:permission-1", "question:question-2"]
        )
        #expect(session?.currentInterruption?.id == "question:question-1")
    }

    @Test("Claude transport duplicates coalesce while identical later questions stay queued")
    func claudeDuplicateDeliveryKeepsLogicalQuestionsSeparate() throws {
        let manager = SessionManager()
        let sessionId = "duplicate-delivery"
        manager.setMuted(sessionId, true)

        func applyQuestion(hook: String, id: String) {
            EventProcessor.apply(
                ClaudeEventParser.parse([
                    "hook_event_name": hook,
                    "session_id": sessionId,
                    "tool_name": "AskUserQuestion",
                    "tool_use_id": id,
                    "tool_input": [
                        "questions": [
                            [
                                "question": "Proceed?",
                                "options": [["label": "Yes"], ["label": "No"]],
                            ]
                        ]
                    ],
                ]),
                agentType: .claudeCode,
                manager: manager
            )
        }

        applyQuestion(hook: "PreToolUse", id: "observation-1")
        applyQuestion(hook: "PermissionRequest", id: "response-1")
        applyQuestion(hook: "PreToolUse", id: "observation-2")
        applyQuestion(hook: "PermissionRequest", id: "response-2")

        let queue = try #require(manager.session(for: sessionId)?.pendingInterruptions)
        #expect(queue.items.map(\.id) == ["question:response-1", "question:response-2"])
        #expect(
            queue.question(toolUseId: "observation-1")?.correlationToolUseIds
                == ["observation-1", "response-1"]
        )
        #expect(
            queue.question(toolUseId: "observation-2")?.correlationToolUseIds
                == ["observation-2", "response-2"]
        )
    }

    // MARK: - Guarding against dropped question answers

    /// Helper that builds a pendingQuestion for AskUserQuestion.
    private func applyAskQuestion(manager: SessionManager, sessionId: String) -> UnifiedSession {
        let askQuestion = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [
                    [
                        "question": "Which approach should we take?",
                        "options": [["label": "A"], ["label": "B"]],
                    ]
                ]
            ],
        ])
        EventProcessor.apply(askQuestion, agentType: .claudeCode, manager: manager)
        return manager.session(for: sessionId)!
    }

    @Test("PostToolUse(AskUserQuestion) clears a stale question banner already settled elsewhere")
    func postToolUseClearsStalePendingQuestion() {
        let manager = SessionManager()
        let session = applyAskQuestion(manager: manager, sessionId: "s1")
        #expect(session.pendingQuestion != nil)

        // Answered in the terminal, so the AskUserQuestion tool completed. Its
        // tool_use_id is a real toolu_ identifier and will not match the locally
        // generated ID on pendingQuestion.
        let questionDone = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": "s1",
            "tool_name": "AskUserQuestion",
            "tool_use_id": "toolu_real",
        ])
        EventProcessor.apply(questionDone, agentType: .claudeCode, manager: manager)
        #expect(session.pendingQuestion == nil)
        #expect(session.status != .permissionWaiting)
    }

    @Test("PostToolUseFailure(AskUserQuestion) also clears a stale question banner")
    func postToolUseFailureClearsStalePendingQuestion() {
        let manager = SessionManager()
        let session = applyAskQuestion(manager: manager, sessionId: "s1")

        let questionFailed = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUseFailure",
            "session_id": "s1",
            "tool_name": "AskUserQuestion",
            "tool_use_id": "toolu_real",
            "error": "schema validation failed",
        ])
        EventProcessor.apply(questionFailed, agentType: .claudeCode, manager: manager)
        #expect(session.pendingQuestion == nil)
    }

    @Test("PostToolUse for a different tool leaves the question banner alone")
    func otherToolPostToolUseKeepsPendingQuestion() {
        let manager = SessionManager()
        let session = applyAskQuestion(manager: manager, sessionId: "s1")

        let otherToolEnd = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": "s1",
            "tool_name": "Read",
            "tool_use_id": "tool-2",
        ])
        EventProcessor.apply(otherToolEnd, agentType: .claudeCode, manager: manager)
        #expect(session.pendingQuestion != nil)
        #expect(session.status == .permissionWaiting)
    }

    @Test("applyPendingExpired switches the question banner to an expired state")
    func applyPendingExpiredMarksQuestionExpired() {
        let manager = SessionManager()
        let session = applyAskQuestion(manager: manager, sessionId: "s1")
        let toolUseId = session.pendingQuestion!.toolUseId
        #expect(session.pendingQuestion?.isExpired == false)

        EventProcessor.applyPendingExpired(
            sessionId: "s1", toolUseId: toolUseId, kind: .askUserQuestion, manager: manager
        )
        #expect(session.pendingQuestion?.isExpired == true)
        // The banner itself stays after expiry so the user can see the answer never landed.
        #expect(session.pendingQuestion != nil)
    }

    @Test("applyPendingExpired ignores questions whose toolUseId does not match")
    func applyPendingExpiredIgnoresMismatchedToolUseId() {
        let manager = SessionManager()
        let session = applyAskQuestion(manager: manager, sessionId: "s1")

        EventProcessor.applyPendingExpired(
            sessionId: "s1", toolUseId: "different-id", kind: .askUserQuestion, manager: manager
        )
        #expect(session.pendingQuestion?.isExpired == false)
    }

    @Test("applyPendingExpired switches the permission banner to canRespond=false")
    func applyPendingExpiredMarksPermissionUnrespondable() {
        let manager = SessionManager()
        let permissionRequest = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_input": ["command": "ls"],
        ])
        EventProcessor.apply(permissionRequest, agentType: .claudeCode, manager: manager)
        let session = manager.session(for: "s1")!
        let toolUseId = session.pendingPermissions.first!.toolUseId
        #expect(session.pendingPermissions.first?.canRespond == true)

        EventProcessor.applyPendingExpired(
            sessionId: "s1", toolUseId: toolUseId, kind: .permissionRequest, manager: manager
        )
        #expect(session.pendingPermissions.first?.canRespond == false)
        // The entry stays after expiry; dismissing it is a user action.
        #expect(session.pendingPermissions.count == 1)
    }

    /// When approval happens in the terminal, the notch never receives an "approved"
    /// notification. All it observes is **the tool's PostToolUse arriving, meaning the
    /// tool ran**. Without treating that as settlement, the list keeps an Approve
    /// button that goes nowhere when pressed.
    ///
    /// Socket-side expiry detection (EOF / TTL) assumes the hook process disconnects,
    /// so when Claude Code settles the request through another path it can take up to
    /// 130 seconds to notice.
    @Test("Approval in the terminal (i.e. the tool ran) clears the pending request")
    func postToolUseClearsPermissionResolvedElsewhere() {
        let manager = SessionManager()
        let sessionId = "s1"
        let permissionRequest = ClaudeEventParser.parse([
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "Bash",
            "tool_input": ["command": "rm -rf build/"],
        ])
        EventProcessor.apply(permissionRequest, agentType: .claudeCode, manager: manager)
        let session = manager.session(for: sessionId)!
        #expect(session.pendingPermissions.count == 1)
        #expect(session.status == .permissionWaiting)

        // A PermissionRequest's toolUseId is generated locally and never matches the
        // real tool_use_id on PostToolUse; confirm the match happens by tool name.
        let toolEnd = ClaudeEventParser.parse([
            "hook_event_name": "PostToolUse",
            "session_id": sessionId,
            "tool_name": "Bash",
            "tool_use_id": "toolu_01ABCDEF",
        ])
        EventProcessor.apply(toolEnd, agentType: .claudeCode, manager: manager)

        #expect(session.pendingPermissions.isEmpty)
        #expect(session.status != .permissionWaiting)
    }

    /// A denial also closes the tool via PostToolUseFailure — equally settled.
    @Test("A tool closing with a failure clears the pending request too")
    func postToolUseFailureClearsPermission() {
        let manager = SessionManager()
        let sessionId = "s1"
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PermissionRequest",
                "session_id": sessionId,
                "tool_name": "ExitPlanMode",
                "tool_input": ["plan": "..."],
            ]),
            agentType: .claudeCode, manager: manager
        )
        let session = manager.session(for: sessionId)!
        #expect(session.pendingPermissions.count == 1)

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PostToolUseFailure",
                "session_id": sessionId,
                "tool_name": "ExitPlanMode",
                "tool_use_id": "toolu_01ZZZ",
                "error": "user rejected",
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.pendingPermissions.isEmpty)
    }

    /// The converse case: **a different tool** finishing must not clear the request.
    /// While subagents run in parallel, an unrelated PostToolUse clearing the pending
    /// approval would close the banner on its own.
    @Test("PostToolUse for a different tool leaves the pending request alone")
    func postToolUseOfOtherToolKeepsPermission() {
        let manager = SessionManager()
        let sessionId = "s1"
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PermissionRequest",
                "session_id": sessionId,
                "tool_name": "Bash",
                "tool_input": ["command": "rm -rf build/"],
            ]),
            agentType: .claudeCode, manager: manager
        )
        let session = manager.session(for: sessionId)!

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PostToolUse",
                "session_id": sessionId,
                "tool_name": "Read",
                "tool_use_id": "toolu_01OTHER",
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.pendingPermissions.count == 1)
        #expect(session.status == .permissionWaiting)
    }

    @Test("Codex keeps a permission when another invocation of the same tool completes")
    func codexSameToolDifferentInvocationKeepsPermission() {
        let manager = SessionManager()
        let sessionId = "codex-plan"
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PermissionRequest",
                "session_id": sessionId,
                "tool_name": "Bash",
                "tool_use_id": "waiting-bash",
                "tool_input": ["command": "git push"],
            ]),
            agentType: .codex, manager: manager
        )
        let session = manager.session(for: sessionId)!

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PostToolUse",
                "session_id": sessionId,
                "tool_name": "Bash",
                "tool_use_id": "other-bash",
            ]),
            agentType: .codex, manager: manager
        )

        #expect(session.pendingPermissions.map(\.toolUseId) == ["waiting-bash"])
        #expect(session.status == .permissionWaiting)

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PostToolUse",
                "session_id": sessionId,
                "tool_name": "Bash",
                "tool_use_id": "waiting-bash",
            ]),
            agentType: .codex, manager: manager
        )

        #expect(session.pendingPermissions.isEmpty)
        #expect(session.status != .permissionWaiting)
    }
}

@Suite("Task list event processing")
@MainActor
struct TaskListEventProcessorTests {
    @Test("planning snapshots create a session and replace its ordered tasks")
    func taskListSnapshotReplacesTasks() {
        let manager = SessionManager()

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PreToolUse",
                "session_id": "plan-session",
                "tool_name": "update_plan",
                "tool_input": [
                    "plan": [
                        ["step": "First", "status": "in_progress"],
                        ["step": "Second", "status": "pending"],
                    ]
                ],
            ]),
            agentType: .codex,
            manager: manager
        )

        let session = manager.session(for: "plan-session")!
        #expect(session.tasks.map(\.subject) == ["First", "Second"])
        #expect(session.tasks.map(\.status) == [.inProgress, .pending])

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PreToolUse",
                "session_id": "plan-session",
                "tool_name": "update_plan",
                "tool_input": [
                    "plan": [
                        ["step": "First", "status": "completed"]
                    ]
                ],
            ]),
            agentType: .codex,
            manager: manager
        )

        #expect(session.tasks.map(\.subject) == ["First"])
        #expect(session.tasks[0].status == .completed)
    }

}

@Suite("StopFailure recovery")
@MainActor
struct StopFailureTests {
    /// Claude Code reports a failure, then recovers from it by compacting and retrying. The
    /// session must not be left red for that.
    @Test("A StopFailure followed by auto-compaction never surfaces as an error")
    func stopFailureFollowedByCompactionIsDropped() async {
        EventProcessor.stopFailureGrace = .milliseconds(50)
        let manager = SessionManager()
        let sessionId = "compacting-session"

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "UserPromptSubmit", "session_id": sessionId,
            ]),
            agentType: .claudeCode, manager: manager
        )

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "StopFailure", "session_id": sessionId,
                "error": "invalid_request",
                "error_details": "prompt is too long",
            ]),
            agentType: .claudeCode, manager: manager
        )
        let session = manager.session(for: sessionId)!
        // Held: nothing is shown while it is still unclear whether the work stopped.
        #expect(session.status != .error)

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "PreCompact", "session_id": sessionId, "trigger": "auto",
            ]),
            agentType: .claudeCode, manager: manager
        )
        #expect(session.status == .compacting)

        // Well past the grace period: the held failure has been evaluated and dropped.
        try? await Task.sleep(for: .milliseconds(600))
        #expect(session.status == .compacting)
    }

    @Test("A StopFailure with no recovery still marks the session as failed")
    func unrecoveredStopFailureBecomesAnError() async {
        EventProcessor.stopFailureGrace = .milliseconds(50)
        let manager = SessionManager()
        let sessionId = "rate-limited-session"

        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "UserPromptSubmit", "session_id": sessionId,
            ]),
            agentType: .claudeCode, manager: manager
        )
        EventProcessor.apply(
            ClaudeEventParser.parse([
                "hook_event_name": "StopFailure", "session_id": sessionId, "error": "rate_limit",
            ]),
            agentType: .claudeCode, manager: manager
        )

        // The confirmation runs on the MainActor, which the rest of the suite is also using, so
        // poll rather than assume it has resumed by any fixed instant.
        var settled = false
        for _ in 0..<60 where !settled {
            try? await Task.sleep(for: .milliseconds(50))
            settled = manager.session(for: sessionId)?.status == .error
        }
        #expect(settled)
    }
}
