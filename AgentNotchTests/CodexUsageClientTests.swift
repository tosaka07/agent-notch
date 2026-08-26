import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Codex usage client", .serialized)
struct CodexUsageClientTests {
    private final class CallState: @unchecked Sendable {
        private let lock = NSLock()
        private var storedCalls = 0

        var calls: Int { lock.withLock { storedCalls } }

        func record() {
            lock.withLock { storedCalls += 1 }
        }
    }

    @Test("App Server response selects the main codex limit and keeps spend semantics separate")
    func parsesUsageBasedLimit() throws {
        let data = Data(
            #"""
            {
              "id": 2,
              "result": {
                "rateLimits": {
                  "primary": {"usedPercent": 99, "resetsAt": 100},
                  "secondary": null,
                  "individualLimit": null,
                  "planType": "fallback"
                },
                "rateLimitsByLimitId": {
                  "codex": {
                    "primary": null,
                    "secondary": null,
                    "individualLimit": {
                      "limit": "60000",
                      "used": "21987.778025984764",
                      "remainingPercent": 63,
                      "resetsAt": 1785542400
                    },
                    "planType": "business"
                  }
                }
              }
            }
            """#.utf8
        )

        let parsed = try CodexAppServerUsageParser.parseResponse(data)
        let snapshot = try #require(parsed)
        #expect(snapshot.planType == "business")
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)

        let allowance = try #require(snapshot.individualLimit)
        #expect(allowance.used == Decimal(string: "21987.778025984764"))
        #expect(allowance.limit == 60_000)
        #expect(allowance.remainingPercent == 63)
        #expect(allowance.resetsAt == Date(timeIntervalSince1970: 1_785_542_400))
        #expect(abs(allowance.usedPercent - 36.64629670997461) < 0.000_000_1)
    }

    @Test("Rolling-window App Server responses remain supported")
    func parsesRollingWindows() throws {
        let data = Data(
            #"""
            {
              "id": 2,
              "result": {
                "rateLimits": {
                  "primary": {"usedPercent": 24.5, "resetsAt": 1774000000},
                  "secondary": {"usedPercent": "51", "resetsAt": "1774600000"},
                  "individualLimit": null,
                  "planType": "plus"
                }
              }
            }
            """#.utf8
        )

        let parsed = try CodexAppServerUsageParser.parseResponse(data)
        let snapshot = try #require(parsed)
        #expect(snapshot.planType == "plus")
        #expect(snapshot.primary?.usedPercent == 24.5)
        #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_774_000_000))
        #expect(snapshot.secondary?.usedPercent == 51)
        #expect(snapshot.individualLimit == nil)
    }

    @Test("Parser accepts numeric spend amounts and ignores an incomplete allowance")
    func parserToleratesSchemaVariants() throws {
        let numeric = Data(
            #"{"id":2,"result":{"rateLimits":{"individualLimit":{"limit":100,"used":20.5,"remainingPercent":"80","resetsAt":"200"},"planType":"business"}}}"#
                .utf8
        )
        let parsedNumeric = try CodexAppServerUsageParser.parseResponse(numeric)
        let numericSnapshot = try #require(parsedNumeric)
        #expect(numericSnapshot.individualLimit?.used == Decimal(string: "20.5"))

        let incomplete = Data(
            #"{"id":2,"result":{"rateLimits":{"individualLimit":{"limit":"100","used":"20"},"planType":"business"}}}"#
                .utf8
        )
        let parsedIncomplete = try CodexAppServerUsageParser.parseResponse(incomplete)
        let incompleteSnapshot = try #require(parsedIncomplete)
        #expect(incompleteSnapshot.individualLimit == nil)
        #expect(incompleteSnapshot.planType == "business")
    }

    @Test("Parser surfaces JSON-RPC errors and rejects missing results")
    func parserErrors() throws {
        let rpcError = Data(
            #"{"id":2,"error":{"code":-32601,"message":"unsupported"}}"#.utf8
        )
        #expect(throws: CodexAppServerError.self) {
            try CodexAppServerUsageParser.parseResponse(rpcError)
        }

        let missingResult = Data(#"{"id":2}"#.utf8)
        #expect(throws: CodexAppServerError.self) {
            try CodexAppServerUsageParser.parseResponse(missingResult)
        }

        let emptyResult = Data(#"{"id":2,"result":{}}"#.utf8)
        let parsedEmpty = try CodexAppServerUsageParser.parseResponse(emptyResult)
        #expect(parsedEmpty == nil)
    }

    @Test("A usable App Server result does not read the rollout fallback")
    func appServerWins() async {
        let expected = CodexUsageSnapshot(
            primary: UsageWindow(usedPercent: 12, resetsAt: nil),
            secondary: nil,
            planType: "plus"
        )
        let fallbackCalls = CallState()
        let client = CodexUsageClient(
            fetchFromAppServer: { expected },
            fetchFromRollout: {
                fallbackCalls.record()
                return nil
            }
        )

        #expect(await client.fetchUsage() == expected)
        #expect(fallbackCalls.calls == 0)
    }

    @Test("App Server failures fall back to rollout usage")
    func failureFallsBack() async {
        let fallback = CodexUsageSnapshot(
            primary: nil,
            secondary: UsageWindow(usedPercent: 42, resetsAt: nil),
            planType: "plus"
        )
        let client = CodexUsageClient(
            fetchFromAppServer: { throw CodexAppServerError.timedOut },
            fetchFromRollout: { fallback }
        )

        #expect(await client.fetchUsage() == fallback)
    }

    @Test("Metadata-only App Server responses prefer a usable rollout window")
    func metadataOnlyFallsBack() async {
        let metadataOnly = CodexUsageSnapshot(
            primary: nil,
            secondary: nil,
            planType: "business"
        )
        let fallback = CodexUsageSnapshot(
            primary: UsageWindow(usedPercent: 35, resetsAt: nil),
            secondary: nil,
            planType: "business"
        )
        let client = CodexUsageClient(
            fetchFromAppServer: { metadataOnly },
            fetchFromRollout: { fallback }
        )

        #expect(await client.fetchUsage() == fallback)
    }

    @Test("An allowance-only App Server result is authoritative")
    func allowanceOnlyAppServerWins() async {
        let allowance = CodexSpendLimit(
            used: 25,
            limit: 100,
            remainingPercent: 75,
            resetsAt: .now
        )
        let expected = CodexUsageSnapshot(
            primary: nil,
            secondary: nil,
            planType: "business",
            individualLimit: allowance
        )
        let fallbackCalls = CallState()
        let client = CodexUsageClient(
            fetchFromAppServer: { expected },
            fetchFromRollout: {
                fallbackCalls.record()
                return nil
            }
        )

        #expect(await client.fetchUsage() == expected)
        #expect(fallbackCalls.calls == 0)
    }

    @Test("A nil App Server result falls back to rollout usage")
    func nilAppServerResultFallsBack() async {
        let fallback = CodexUsageSnapshot(
            primary: UsageWindow(usedPercent: 15, resetsAt: nil),
            secondary: nil,
            planType: "plus"
        )
        let client = CodexUsageClient(
            fetchFromAppServer: { nil },
            fetchFromRollout: { fallback }
        )

        #expect(await client.fetchUsage() == fallback)
    }

    @Test("Executable resolver works without a login-shell PATH")
    func executableResolverUsesKnownHomeLocation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-resolver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let codex = bin.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: codex.path
        )

        let resolved = CodexExecutableResolver.resolve(
            environment: ["PATH": ""],
            homeDirectory: root
        )

        #expect(resolved?.path == codex.path)
    }

    @Test("Executable resolver finds Codex installed under a version-managed Node")
    func executableResolverUsesVersionManager() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-nvm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent(".nvm/versions/node/v24.1.0/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let codex = bin.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: codex.path
        )

        let resolved = CodexExecutableResolver.resolve(
            environment: ["PATH": ""],
            homeDirectory: root
        )

        #expect(resolved?.path == codex.path)
    }

    @Test("JSON-RPC waits for initialize id, ignores notifications, and sends the read request")
    func processHandshake() async throws {
        let fixture = try makeScript(
            #"""
            log_path="$1"
            IFS= read -r initialize
            printf '%s\n' "$initialize" >> "$log_path"
            printf '%s\n' '{"method":"account/rateLimits/updated","params":{}}'
            printf '%s\n' 'not-json'
            printf '%s\n' '{"id":99,"result":{"ignored":true}}'
            printf '%s\n' '{"id":1,"result":{"userAgent":"fake"}}'
            IFS= read -r initialized
            printf '%s\n' "$initialized" >> "$log_path"
            IFS= read -r rate_limits
            printf '%s\n' "$rate_limits" >> "$log_path"
            printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":null,"secondary":null,"individualLimit":{"limit":"100","used":"25","remainingPercent":75,"resetsAt":200},"planType":"business"}}}'
            """#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let log = fixture.directory.appendingPathComponent("requests.jsonl")

        let response = try await CodexAppServerProcess(
            executableURL: fixture.script,
            arguments: [log.path],
            timeout: 2
        ).requestRateLimits()
        let parsed = try CodexAppServerUsageParser.parseResponse(response)
        let snapshot = try #require(parsed)

        #expect(snapshot.individualLimit?.usedPercent == 25)
        let requests = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n")
            .map { try jsonObject(String($0)) }
        #expect(requests.count == 3)
        #expect((requests[0]["id"] as? NSNumber)?.intValue == 1)
        #expect(requests[0]["method"] as? String == "initialize")
        #expect(requests[1]["id"] == nil)
        #expect(requests[1]["method"] as? String == "initialized")
        #expect((requests[2]["id"] as? NSNumber)?.intValue == 2)
        #expect(requests[2]["method"] as? String == "account/rateLimits/read")
    }

    @Test("JSON-RPC errors are surfaced without waiting for timeout")
    func processRPCError() async throws {
        let fixture = try makeScript(
            #"""
            IFS= read -r initialize
            printf '%s\n' '{"id":1,"error":{"code":-32601,"message":"unsupported"}}'
            """#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        do {
            _ = try await CodexAppServerProcess(
                executableURL: fixture.script,
                arguments: [],
                timeout: 2
            ).requestRateLimits()
            Issue.record("Expected an RPC error")
        } catch let error as CodexAppServerError {
            guard case .rpc(let message) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(message == "unsupported")
        }
    }

    @Test("A response without result is rejected")
    func processInvalidResponse() async throws {
        let fixture = try makeScript(
            #"""
            IFS= read -r initialize
            printf '%s\n' '{"id":1}'
            """#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        do {
            _ = try await CodexAppServerProcess(
                executableURL: fixture.script,
                arguments: [],
                timeout: 2
            ).requestRateLimits()
            Issue.record("Expected an invalid response error")
        } catch let error as CodexAppServerError {
            guard case .invalidResponse = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("Early process exit is reported")
    func processExit() async throws {
        let fixture = try makeScript(
            #"""
            IFS= read -r initialize
            exit 7
            """#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        do {
            _ = try await CodexAppServerProcess(
                executableURL: fixture.script,
                arguments: [],
                timeout: 2
            ).requestRateLimits()
            Issue.record("Expected a process exit error")
        } catch let error as CodexAppServerError {
            guard case .terminated(let status) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(status == 7)
        }
    }

    @Test("A process that cannot launch reports a launch error")
    func processLaunchFailure() async {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-codex-\(UUID().uuidString)")

        do {
            _ = try await CodexAppServerProcess(
                executableURL: missing,
                arguments: [],
                timeout: 2
            ).requestRateLimits()
            Issue.record("Expected a launch error")
        } catch let error as CodexAppServerError {
            guard case .launch = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("An unresponsive App Server is terminated at the configured timeout")
    func processTimeout() async throws {
        let fixture = try makeScript(
            #"""
            IFS= read -r initialize
            IFS= read -r never
            """#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        do {
            _ = try await CodexAppServerProcess(
                executableURL: fixture.script,
                arguments: [],
                timeout: 0.05
            ).requestRateLimits()
            Issue.record("Expected a timeout")
        } catch let error as CodexAppServerError {
            guard case .timedOut = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("Cancelling a request terminates the child process")
    func processCancellation() async throws {
        let fixture = try makeScript(
            #"""
            IFS= read -r initialize
            IFS= read -r never
            """#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let process = CodexAppServerProcess(
            executableURL: fixture.script,
            arguments: [],
            timeout: 2
        )
        let task = Task {
            try await process.requestRateLimits()
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("App Server errors provide actionable descriptions")
    func errorDescriptions() {
        #expect(CodexAppServerError.executableNotFound.localizedDescription.contains("not found"))
        #expect(CodexAppServerError.launch("boom").localizedDescription.contains("boom"))
        #expect(CodexAppServerError.rpc("bad method").localizedDescription.contains("bad method"))
        #expect(CodexAppServerError.invalidResponse.localizedDescription.contains("invalid"))
        #expect(CodexAppServerError.responseTooLarge.localizedDescription.contains("size"))
        #expect(CodexAppServerError.timedOut.localizedDescription.contains("timed out"))
        #expect(CodexAppServerError.terminated(7).localizedDescription.contains("7"))
    }

    private func makeScript(_ body: String) throws -> (directory: URL, script: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-app-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fake-codex")
        try ("#!/bin/sh\nset -eu\n" + body + "\n")
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: script.path
        )
        return (directory, script)
    }

    private func jsonObject(_ line: String) throws -> [String: Any] {
        let data = try #require(line.data(using: .utf8))
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
