import Foundation
import Testing

@testable import AgentNotchCore

@Suite("HookHandler response control tests")
struct HookHandlerTests {
    @Test("Hook invocation waits for EOF and reads chunked JSON completely")
    func readsChunkedHookInputToEnd() async {
        let pipe = Pipe()
        let expected = Data(
            """
            {"hook_event_name":"PostToolUse","tool_response":"large response"}
            """.utf8
        )
        let splitIndex = expected.count / 2
        let firstChunk = expected.prefix(splitIndex)
        let secondChunk = expected.suffix(from: splitIndex)

        pipe.fileHandleForWriting.write(firstChunk)
        let writer = Task.detached {
            try? await Task.sleep(for: .milliseconds(50))
            pipe.fileHandleForWriting.write(secondChunk)
            try? pipe.fileHandleForWriting.close()
        }

        let actual = HookInvocationInput.readAll(from: pipe.fileHandleForReading)
        await writer.value

        #expect(actual == expected)
    }

    @Test("Terminal handoff marker is consumed internally instead of reaching hook stdout")
    func terminalHandoffSuppressesHookOutput() {
        let response: [String: Any] = [HookResponseControl.respondInTerminalKey: true]

        #expect(HookResponseControl.shouldEmitToAgent(response) == false)
    }

    @Test("Permission decisions are emitted to the agent")
    func permissionDecisionIsEmitted() {
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "allow"],
            ]
        ]

        #expect(HookResponseControl.shouldEmitToAgent(response) == true)
    }
}
