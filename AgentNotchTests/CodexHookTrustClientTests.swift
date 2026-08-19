import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Codex hook trust client")
struct CodexHookTrustClientTests {
    private let expectedCommand = "agent-notch hook --agent codex"

    @Test("A modified Agent Notch hook requires review")
    func modifiedHookNeedsReview() throws {
        let response = responseData(
            hooks: [
                hook(command: expectedCommand, trustStatus: "modified")
            ]
        )

        #expect(
            try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            ) == .needsReview
        )
    }

    @Test("Unrelated modified hooks do not taint Agent Notch")
    func unrelatedHookIsIgnored() throws {
        let response = responseData(
            hooks: [
                hook(command: "other-app hook", trustStatus: "modified"),
                hook(command: expectedCommand, trustStatus: "trusted"),
            ]
        )

        #expect(
            try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            ) == .trusted
        )
    }

    @Test("A disabled Agent Notch hook is reported separately")
    func disabledHook() throws {
        let response = responseData(
            hooks: [
                hook(command: expectedCommand, trustStatus: "trusted", enabled: false)
            ]
        )

        #expect(
            try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            ) == .disabled
        )
    }

    @Test("Managed Agent Notch hooks are trusted by policy")
    func managedHook() throws {
        let response = responseData(
            hooks: [
                hook(
                    command: expectedCommand,
                    trustStatus: "managed",
                    isManaged: true
                )
            ]
        )

        #expect(
            try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            ) == .trusted
        )
    }

    @Test("Missing Agent Notch hooks are distinguishable from trusted hooks")
    func missingHook() throws {
        let response = responseData(
            hooks: [
                hook(command: "other-app hook", trustStatus: "trusted")
            ]
        )

        #expect(
            try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            ) == .notFound
        )
    }

    @Test("hooks/list JSON-RPC errors are surfaced")
    func rpcError() {
        let response = Data(
            #"{"id":2,"error":{"code":-32601,"message":"unsupported"}}"#.utf8
        )

        #expect(throws: CodexAppServerError.self) {
            try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            )
        }
    }

    @Test("Reads the installed Codex hook trust state through App Server")
    func liveHookTrustInspection() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AGENT_NOTCH_CODEX_HOOK_TRUST_INTEGRATION"] == "1" else {
            return
        }

        let expectedState: CodexHookTrustState =
            environment["AGENT_NOTCH_EXPECTED_HOOK_TRUST"] == "needsReview"
            ? .needsReview
            : .trusted
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
        let data = try Data(contentsOf: hooksURL)
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(root["hooks"] as? [String: Any])
        let command = try #require(
            hooks.values
                .compactMap { $0 as? [[String: Any]] }
                .flatMap { $0 }
                .compactMap { $0["hooks"] as? [[String: Any]] }
                .flatMap { $0 }
                .compactMap { $0["command"] as? String }
                .first { $0.contains("agent-notch") }
        )

        let actualState = await CodexHookTrustClient.shared.inspect(
            expectedCommand: command
        )
        #expect(actualState == expectedState)
    }

    private func responseData(hooks: [[String: Any]]) -> Data {
        try! JSONSerialization.data(
            withJSONObject: [
                "id": 2,
                "result": [
                    "data": [
                        [
                            "cwd": "/tmp/project",
                            "hooks": hooks,
                            "warnings": [],
                            "errors": [],
                        ]
                    ]
                ],
            ]
        )
    }

    private func hook(
        command: String,
        trustStatus: String,
        enabled: Bool = true,
        isManaged: Bool = false
    ) -> [String: Any] {
        [
            "key": "/tmp/hooks.json:session_start:0:0",
            "eventName": "SessionStart",
            "handlerType": "command",
            "command": command,
            "enabled": enabled,
            "isManaged": isManaged,
            "currentHash": "sha256:current",
            "trustStatus": trustStatus,
        ]
    }
}
