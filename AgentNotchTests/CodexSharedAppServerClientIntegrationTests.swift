import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Codex shared App Server integration")
struct CodexSharedAppServerClientIntegrationTests {
    private final class ReadyFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = false

        var value: Bool { lock.withLock { storage } }

        func set() {
            lock.withLock { storage = true }
        }
    }

    @Test("Only threads already loaded by the shared server are eligible for resume")
    func loadedMembershipGate() {
        #expect(
            CodexSharedAppServerClient.eligibleThreadIds(
                desired: ["shared", "embedded"],
                loaded: ["shared", "unrelated"]
            ) == ["shared"]
        )
    }

    @Test("Connects through the installed CLI's official Unix control socket")
    func connectsToInstalledCLI() async throws {
        guard ProcessInfo.processInfo.environment["AGENT_NOTCH_CODEX_INTEGRATION"] == "1" else {
            return
        }
        let executableURL = try #require(CodexExecutableResolver.resolve())
        let ready = ReadyFlag()
        let client = CodexSharedAppServerClient(
            executableURL: executableURL,
            onRequest: { _ in },
            onResolved: { _ in },
            onReady: { ready.set() }
        )
        client.start()
        defer { client.stop() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while !ready.value, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(ready.value)
    }
}
