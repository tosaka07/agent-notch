import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Codex rollout question monitor")
struct CodexRolloutQuestionMonitorTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [[CodexRolloutQuestion]] = []

        func append(_ value: [CodexRolloutQuestion]) {
            lock.withLock { values.append(value) }
        }

        var latest: [CodexRolloutQuestion]? {
            lock.withLock { values.last }
        }
    }

    @Test("A watched rollout recovers and resolves a question without a global directory scan")
    func watchesKnownRollout() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-rollout-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        try append(
            #"{"timestamp":"2026-07-27T04:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp"}}"#,
            to: url
        )

        let recorder = Recorder()
        let monitor = CodexRolloutQuestionMonitor { _, questions in
            recorder.append(questions)
        }
        monitor.start()
        monitor.setWatchedSessions(["thread-1": url.path])
        defer { monitor.stop() }

        try append(
            ##"{"timestamp":"2026-07-27T04:00:01.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","arguments":"{\"questions\":[{\"id\":\"target\",\"question\":\"Where?\",\"options\":[{\"label\":\"Staging\"}]}]}","call_id":"call-1","internal_chat_message_metadata_passthrough":{"turn_id":"turn-1"}}}"##,
            to: url
        )
        try await waitUntil {
            recorder.latest?.first?.callId == "call-1"
        }

        try append(
            #"{"timestamp":"2026-07-27T04:00:02.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call-1","output":"{\"answers\":{}}"}}"#,
            to: url
        )
        try await waitUntil {
            recorder.latest?.isEmpty == true
        }
    }

    private func append(_ line: String, to url: URL) throws {
        let data = Data((line + "\n").utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @Sendable () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for rollout monitor")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
