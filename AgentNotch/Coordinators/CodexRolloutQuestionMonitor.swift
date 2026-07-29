import AgentNotchCore
import Foundation

protocol CodexRolloutQuestionMonitoring: AnyObject {
    func start()
    func stop()
    func setWatchedSessions(_ transcriptPathBySessionId: [String: String])
}

/// Watches only rollout files already associated with visible Codex sessions.
///
/// A lightweight metadata poll is intentional here. Rollout paths may be
/// restored before the file is reachable, renamed during runtime recovery, or
/// supplied after SessionStart. Checking size/mtime handles all three without
/// recursively watching `~/.codex/sessions` or depending on undocumented IPC.
/// File contents are parsed only after a metadata change.
final class CodexRolloutQuestionMonitor: CodexRolloutQuestionMonitoring, @unchecked Sendable {
    private struct FileStamp: Equatable {
        let size: UInt64
        let modificationDate: Date?
    }

    private let queue = DispatchQueue(
        label: "com.agentnotch.codex-rollout-questions",
        qos: .utility
    )
    private let onSnapshot: @Sendable (String, [CodexRolloutQuestion]) -> Void
    private var transcriptPathBySessionId: [String: String] = [:]
    private var stamps: [String: FileStamp] = [:]
    private var timer: DispatchSourceTimer?

    init(
        onSnapshot: @escaping @Sendable (String, [CodexRolloutQuestion]) -> Void
    ) {
        self.onSnapshot = onSnapshot
    }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: .milliseconds(400),
                leeway: .milliseconds(100)
            )
            timer.setEventHandler { [weak self] in
                self?.scanChangedFiles()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            timer?.cancel()
            timer = nil
            transcriptPathBySessionId = [:]
            stamps = [:]
        }
    }

    func setWatchedSessions(_ transcriptPathBySessionId: [String: String]) {
        queue.async { [weak self] in
            guard let self else { return }
            let changedSessionIds = Set(
                transcriptPathBySessionId.compactMap { sessionId, path in
                    self.transcriptPathBySessionId[sessionId] == path ? nil : sessionId
                }
            )
            self.transcriptPathBySessionId = transcriptPathBySessionId
            self.stamps = self.stamps.filter { transcriptPathBySessionId[$0.key] != nil }
            for sessionId in changedSessionIds {
                self.stamps.removeValue(forKey: sessionId)
            }
            self.scanChangedFiles()
        }
    }

    private func scanChangedFiles() {
        for (sessionId, path) in transcriptPathBySessionId {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let size = (attributes[.size] as? NSNumber)?.uint64Value
            else { continue }
            let stamp = FileStamp(
                size: size,
                modificationDate: attributes[.modificationDate] as? Date
            )
            guard stamps[sessionId] != stamp else { continue }
            stamps[sessionId] = stamp
            onSnapshot(
                sessionId,
                CodexTranscriptReader.pendingUserInputQuestions(path: path)
            )
        }
    }
}
