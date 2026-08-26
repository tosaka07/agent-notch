import AgentNotchCore
import Foundation

/// Persists the durable part of `UnifiedSession` as one versioned, atomic JSON snapshot.
///
/// This is intentionally the only GUI module that knows the file location, schema envelope,
/// debounce policy, and restore order. `SessionManager` only exposes snapshots and a change seam.
@MainActor
final class SessionSnapshotPersistenceCoordinator {
    private let sessionManager: SessionManager
    private let fileManager: FileManager
    private let fileURL: URL
    private let debounceInterval: TimeInterval
    private let now: () -> Date
    private var pendingSave: DispatchWorkItem?
    private var hasUnsavedChanges = false

    init(
        sessionManager: SessionManager,
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        debounceInterval: TimeInterval = 0.3,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionManager = sessionManager
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.debounceInterval = debounceInterval
        self.now = now
    }

    /// Restores synchronously before the socket and UI start, then begins autosaving.
    func start(
        timeoutSeconds: Int,
        isProcessAlive: SessionManager.ProcessAliveCheck = SessionManager.defaultIsProcessAlive
    ) {
        let needsMigration = restoreIfPresent()
        if needsMigration {
            hasUnsavedChanges = true
            flush()
        }
        sessionManager.onSessionChange = { [weak self] in
            self?.scheduleSave()
        }
        _ = sessionManager.sweepStale(
            timeoutSeconds: timeoutSeconds,
            isProcessAlive: isProcessAlive,
            now: now()
        )
    }

    /// Flushes synchronously so a clean app termination does not lose the final debounce window.
    func stop() {
        pendingSave?.cancel()
        pendingSave = nil
        if hasUnsavedChanges {
            flush()
        }
        sessionManager.onSessionChange = nil
    }

    /// Internal for deterministic tests and explicit lifecycle flushes.
    func flush() {
        let envelope = SessionSnapshotEnvelope(
            savedAt: now(),
            sessions: sessionManager.sessionSnapshots
        )

        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            pendingSave = nil
            hasUnsavedChanges = false
            Log.persistence.debug("Saved \(envelope.sessions.count) session snapshots")
        } catch {
            Log.persistence.error("Failed to save session snapshots: \(error.localizedDescription)")
        }
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return
            applicationSupport
            .appendingPathComponent("Agent Notch", isDirectory: true)
            .appendingPathComponent("sessions-v1.json", isDirectory: false)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        hasUnsavedChanges = true
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// Returns true when a supported older schema was restored and should be
    /// rewritten immediately in the current format.
    private func restoreIfPresent() -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(SessionSnapshotEnvelope.self, from: data)
            guard
                envelope.schemaVersion >= SessionSnapshotEnvelope.minimumSupportedSchemaVersion,
                envelope.schemaVersion <= SessionSnapshotEnvelope.currentSchemaVersion
            else {
                Log.persistence.warning(
                    "Ignoring unsupported session snapshot schema \(envelope.schemaVersion)"
                )
                return false
            }
            sessionManager.restoreSessions(from: envelope.sessions)
            Log.persistence.info("Restored \(envelope.sessions.count) session snapshots")
            return envelope.schemaVersion < SessionSnapshotEnvelope.currentSchemaVersion
        } catch {
            // Persistence must never prevent Agent Notch from opening. The next successful
            // autosave atomically replaces a corrupt file.
            Log.persistence.error("Ignoring unreadable session snapshots: \(error.localizedDescription)")
            return false
        }
    }
}
