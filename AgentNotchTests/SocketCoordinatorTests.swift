import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Socket coordinator integration", .serialized)
@MainActor
struct SocketCoordinatorTests {
    @Test("A hook delivered over the real socket becomes observable session state")
    func hookCreatesSession() async throws {
        let socketPath = "/tmp/agent-notch-coordinator-\(UUID().uuidString).sock"
        let manager = SessionManager()
        let coordinator = SocketCoordinator(
            sessionManager: manager,
            socketPath: socketPath
        )
        coordinator.start()
        defer { coordinator.stop() }
        try await waitUntil { FileManager.default.fileExists(atPath: socketPath) }

        let input = Data(
            """
            {
              "hook_event_name": "SessionStart",
              "session_id": "socket-session",
              "model": "gpt-5",
              "cwd": "/tmp/socket-project",
              "source": "startup"
            }
            """.utf8
        )
        #expect(
            HookHandler.handle(
                inputData: input,
                agentType: "codex",
                socketPath: socketPath
            ) == nil
        )
        try await waitUntil { manager.session(for: "socket-session") != nil }

        let session = try #require(manager.session(for: "socket-session"))
        #expect(session.agentType == .codex)
        #expect(session.model == "gpt-5")
        #expect(session.cwd == "/tmp/socket-project")
        #expect(session.status == .idle)
        #expect(session.presence == .live)
    }

    @Test("Approving in the UI answers the original hook and clears pending state")
    func approvalRoundTrip() async throws {
        let socketPath = "/tmp/agent-notch-coordinator-\(UUID().uuidString).sock"
        let manager = SessionManager()
        let coordinator = SocketCoordinator(
            sessionManager: manager,
            socketPath: socketPath
        )
        coordinator.start()
        defer { coordinator.stop() }
        try await waitUntil { FileManager.default.fileExists(atPath: socketPath) }

        let input = Data(
            """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "permission-session",
              "tool_name": "Bash",
              "tool_use_id": "permission-tool",
              "tool_input": {"command": "swift test"}
            }
            """.utf8
        )
        let responseTask = Task.detached {
            HookHandler.handle(
                inputData: input,
                agentType: "codex",
                socketPath: socketPath
            )
        }
        try await waitUntil {
            manager.session(for: "permission-session")?.pendingPermissions.count == 1
        }

        coordinator.permissionActions.approve(
            "permission-session",
            "permission-tool"
        )

        let output = try #require(await responseTask.value)
        let response = try #require(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let hookOutput = try #require(
            response["hookSpecificOutput"] as? [String: Any]
        )
        let decision = try #require(hookOutput["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        #expect(
            manager.session(for: "permission-session")?.pendingPermissions.isEmpty
                == true
        )
    }

    @Test("Denying in the UI returns the reason and clears pending state")
    func denialRoundTrip() async throws {
        let socketPath = "/tmp/agent-notch-coordinator-\(UUID().uuidString).sock"
        let manager = SessionManager()
        let coordinator = SocketCoordinator(
            sessionManager: manager,
            socketPath: socketPath
        )
        coordinator.start()
        defer { coordinator.stop() }
        try await waitUntil { FileManager.default.fileExists(atPath: socketPath) }

        let input = Data(
            """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "denial-session",
              "tool_name": "Bash",
              "tool_use_id": "denial-tool",
              "tool_input": {"command": "rm important-file"}
            }
            """.utf8
        )
        let responseTask = Task.detached {
            HookHandler.handle(
                inputData: input,
                agentType: "codex",
                socketPath: socketPath
            )
        }
        try await waitUntil {
            manager.session(for: "denial-session")?.pendingPermissions.count == 1
        }

        coordinator.permissionActions.deny(
            "denial-session",
            "denial-tool",
            "Not approved"
        )

        let output = try #require(await responseTask.value)
        let response = try #require(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let hookOutput = try #require(
            response["hookSpecificOutput"] as? [String: Any]
        )
        let decision = try #require(hookOutput["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] as? String == "Not approved")
        #expect(
            manager.session(for: "denial-session")?.pendingPermissions.isEmpty
                == true
        )
    }

    @Test("Answering a question preserves its schema and clears pending state")
    func questionRoundTrip() async throws {
        let socketPath = "/tmp/agent-notch-coordinator-\(UUID().uuidString).sock"
        let manager = SessionManager()
        let coordinator = SocketCoordinator(
            sessionManager: manager,
            socketPath: socketPath
        )
        coordinator.start()
        defer { coordinator.stop() }
        try await waitUntil { FileManager.default.fileExists(atPath: socketPath) }

        let input = Data(
            """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "question-session",
              "tool_name": "AskUserQuestion",
              "tool_use_id": "question-tool",
              "tool_input": {
                "questions": [{
                  "question": "Targets?",
                  "header": "Deploy",
                  "multiSelect": true,
                  "options": [
                    {"label": "Staging", "description": "Test"},
                    {"label": "Production", "description": "Ship"}
                  ]
                }]
              }
            }
            """.utf8
        )
        let responseTask = Task.detached {
            HookHandler.handle(
                inputData: input,
                agentType: "claude",
                socketPath: socketPath
            )
        }
        try await waitUntil {
            manager.session(for: "question-session")?.pendingQuestion != nil
        }

        coordinator.permissionActions.answerQuestion(
            "question-session",
            "question-tool",
            ["Targets?": ["Staging", "Production"]]
        )

        let output = try #require(await responseTask.value)
        let response = try #require(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let hookOutput = try #require(
            response["hookSpecificOutput"] as? [String: Any]
        )
        let decision = try #require(hookOutput["decision"] as? [String: Any])
        let updatedInput = try #require(
            decision["updatedInput"] as? [String: Any]
        )
        let answers = try #require(updatedInput["answers"] as? [String: String])
        #expect(answers == ["Targets?": "Staging / Production"])
        #expect(manager.session(for: "question-session")?.pendingQuestion == nil)
    }

    @Test("A permission with no live response path stays visible as expired until dismissed")
    func failedDeliveryStaysVisibleUntilDismissed() throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "expired-session", agentType: .codex)
        session.status = .permissionWaiting
        session.pendingPermissions = [
            PermissionRequest(
                id: "expired-permission",
                agentType: .codex,
                sessionId: session.id,
                toolName: "Bash",
                toolInput: ["command": "swift test"],
                toolUseId: "expired-tool",
                timestamp: .now,
                canRespond: true
            )
        ]
        let coordinator = SocketCoordinator(sessionManager: manager)
        let actions = coordinator.permissionActions

        actions.approve("expired-session", "expired-tool")

        let expired = try #require(session.pendingPermissions.first)
        #expect(expired.canRespond == false)
        #expect(session.status == .permissionWaiting)

        actions.dismissExpired("expired-session", "expired-tool")

        #expect(session.pendingPermissions.isEmpty)
        #expect(session.status == .thinking)
    }

    @Test("A question with no live response path stays visible as expired until dismissed")
    func failedQuestionDeliveryStaysVisibleUntilDismissed() throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "expired-question", agentType: .claudeCode)
        session.status = .permissionWaiting
        session.pendingQuestion = PendingQuestion(
            toolUseId: "question-tool",
            questions: [
                AskQuestionInfo.Question(
                    question: "Proceed?",
                    header: nil,
                    multiSelect: false,
                    options: [],
                    allowsOther: true
                )
            ]
        )
        let coordinator = SocketCoordinator(sessionManager: manager)
        let actions = coordinator.permissionActions

        actions.answerQuestion(
            session.id,
            "question-tool",
            ["Proceed?": ["Yes"]]
        )

        let expired = try #require(session.pendingQuestion)
        #expect(expired.phase == .expired)
        #expect(session.status == .permissionWaiting)

        actions.dismissExpired(session.id, "question-tool")

        #expect(session.pendingQuestion == nil)
        #expect(session.status == .thinking)
    }

    @Test("Returning a permission to the terminal closes the hook without a decision")
    func terminalHandoff() async throws {
        let socketPath = "/tmp/agent-notch-coordinator-\(UUID().uuidString).sock"
        let manager = SessionManager()
        let coordinator = SocketCoordinator(
            sessionManager: manager,
            socketPath: socketPath
        )
        coordinator.start()
        defer { coordinator.stop() }
        try await waitUntil { FileManager.default.fileExists(atPath: socketPath) }

        let input = Data(
            """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "terminal-session",
              "tool_name": "Bash",
              "tool_use_id": "terminal-tool",
              "tool_input": {"command": "swift test"}
            }
            """.utf8
        )
        let responseTask = Task.detached {
            HookHandler.handle(
                inputData: input,
                agentType: "codex",
                socketPath: socketPath
            )
        }
        try await waitUntil {
            manager.session(for: "terminal-session")?.pendingPermissions.count == 1
        }

        coordinator.permissionActions.respondInTerminal(
            "terminal-session",
            "terminal-tool"
        )

        #expect(await responseTask.value == nil)
        #expect(
            manager.session(for: "terminal-session")?.pendingPermissions.isEmpty
                == true
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
