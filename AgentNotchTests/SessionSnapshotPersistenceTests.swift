import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Session snapshot persistence")
@MainActor
struct SessionSnapshotPersistenceTests {
    @Test("Round trip restores card-visible state without actionable runtime state")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-session-snapshot-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("sessions-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = SessionManager()
        let writer = SessionSnapshotPersistenceCoordinator(
            sessionManager: source,
            fileURL: fileURL,
            debounceInterval: 60
        )
        writer.start(timeoutSeconds: 0, isProcessAlive: { _ in true })

        let session = source.getOrCreateSession(id: "codex-session", agentType: .codex)
        session.model = "gpt-5"
        session.cwd = "/tmp"
        session.status = .permissionWaiting
        session.pid = 123
        session.sessionTitle = "Persistent work"
        session.firstUserPrompt = "Implement persistence"
        session.lastUserPrompt = "Verify restored card content"
        session.lastAssistantMessage = "Work in progress"
        session.totalInputTokens = 1200
        session.estimatedCost = 0.42
        session.tasks = [
            AgentTask(id: "task-1", subject: "Persist the plan", status: .inProgress)
        ]
        session.pendingPermissions = [
            PermissionRequest(
                id: "permission",
                agentType: .codex,
                sessionId: session.id,
                toolName: "Bash",
                toolInput: ["command": "secret command"],
                toolUseId: "tool-use",
                timestamp: Date(),
                canRespond: true
            )
        ]

        source.notifyChange()
        // A clean shutdown must flush even though the long debounce has not fired.
        writer.stop()

        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(raw.contains("Persistent work"))
        #expect(raw.contains("secret command") == false)

        let restoredManager = SessionManager()
        let reader = SessionSnapshotPersistenceCoordinator(
            sessionManager: restoredManager,
            fileURL: fileURL
        )
        reader.start(timeoutSeconds: 0, isProcessAlive: { _ in true })
        defer { reader.stop() }

        let restored = try #require(restoredManager.session(for: "codex-session"))
        #expect(restored.presence == .restored)
        #expect(restored.status == .idle)
        #expect(restored.lastKnownStatus == .permissionWaiting)
        #expect(restored.pendingPermissions.isEmpty)
        #expect(restored.pendingQuestion == nil)
        #expect(restored.sessionTitle == "Persistent work")
        #expect(restored.firstUserPrompt == "Implement persistence")
        #expect(restored.lastUserPrompt == "Verify restored card content")
        #expect(restored.lastAssistantMessage == "Work in progress")
        #expect(restored.totalInputTokens == 1200)
        #expect(restored.estimatedCost == 0.42)
        #expect(restored.tasks.map(\.id) == ["task-1"])
        #expect(restored.tasks.map(\.subject) == ["Persist the plan"])
        #expect(restored.tasks.map(\.status) == [.inProgress])
    }

    @Test("A restored session shows terminal jump after its destination is revalidated")
    func restoredSessionTerminalJumpAvailability() throws {
        let source = UnifiedSession(id: "terminal-session", agentType: .codex)
        source.presence = .live
        source.pid = 12_345
        source.terminalAppName = "Terminal"
        source.terminalInfoResolved = true

        let restored = SessionSnapshot(session: source).makeRestoredSession()

        #expect(restored.presence == .restored)
        #expect(restored.pid == 12_345)
        #expect(restored.terminalInfoResolved == false)

        // A successful startup revalidation proves that this restored destination is actionable.
        restored.terminalAppName = "Terminal"
        restored.terminalInfoResolved = true

        #expect(restored.isTerminalJumpAvailable)
    }

    @Test("A corrupt snapshot never prevents startup")
    func corruptSnapshotIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-corrupt-snapshot-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("sessions-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: fileURL)

        let manager = SessionManager()
        let coordinator = SessionSnapshotPersistenceCoordinator(
            sessionManager: manager,
            fileURL: fileURL
        )
        coordinator.start(timeoutSeconds: 3600)
        defer { coordinator.stop() }

        #expect(manager.allSessions.isEmpty)
    }

    @Test("A session change is persisted after the debounce without stopping")
    func debouncedAutosave() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-debounced-snapshot-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("sessions-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let manager = SessionManager()
        let coordinator = SessionSnapshotPersistenceCoordinator(
            sessionManager: manager,
            fileURL: fileURL,
            debounceInterval: 0.01
        )
        coordinator.start(timeoutSeconds: 0, isProcessAlive: { _ in true })
        defer { coordinator.stop() }

        let session = manager.getOrCreateSession(id: "autosaved", agentType: .claudeCode)
        session.sessionTitle = "Saved without termination"
        manager.notifyChange()

        for _ in 0..<200 where !FileManager.default.fileExists(atPath: fileURL.path) {
            try await Task.sleep(for: .milliseconds(5))
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(SessionSnapshotEnvelope.self, from: data)
        #expect(envelope.sessions.map(\.id) == ["autosaved"])
    }

    @Test("A snapshot from a newer schema is left untouched and not restored")
    func newerSchemaIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-future-snapshot-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("sessions-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = UnifiedSession(id: "from-the-future", agentType: .codex)
        let envelope = SessionSnapshotEnvelope(
            schemaVersion: SessionSnapshotEnvelope.currentSchemaVersion + 1,
            sessions: [SessionSnapshot(session: source)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(envelope)
        try original.write(to: fileURL)

        let manager = SessionManager()
        let coordinator = SessionSnapshotPersistenceCoordinator(
            sessionManager: manager,
            fileURL: fileURL
        )
        coordinator.start(timeoutSeconds: 0, isProcessAlive: { _ in true })
        defer { coordinator.stop() }

        #expect(manager.allSessions.isEmpty)
        let persisted = try Data(contentsOf: fileURL)
        #expect(persisted == original)
    }

    @Test("Schema v1 restores without tasks and is rewritten as v2")
    func schemaV1MigratesToV2() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-v1-snapshot-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("sessions-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = UnifiedSession(id: "legacy", agentType: .codex)
        source.tasks = [AgentTask(id: "not-in-v1", subject: "Must not leak")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let currentData = try encoder.encode(
            SessionSnapshotEnvelope(sessions: [SessionSnapshot(session: source)])
        )
        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyJSON["schemaVersion"] = 1
        var sessions = try #require(legacyJSON["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "tasks")
        legacyJSON["sessions"] = sessions
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        try legacyData.write(to: fileURL)

        let manager = SessionManager()
        let coordinator = SessionSnapshotPersistenceCoordinator(
            sessionManager: manager,
            fileURL: fileURL
        )
        coordinator.start(timeoutSeconds: 0, isProcessAlive: { _ in true })
        defer { coordinator.stop() }

        let restored = try #require(manager.session(for: "legacy"))
        #expect(restored.tasks.isEmpty)

        let migratedData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(SessionSnapshotEnvelope.self, from: migratedData)
        #expect(migrated.schemaVersion == SessionSnapshotEnvelope.currentSchemaVersion)
        #expect(migrated.schemaVersion == 2)
    }
}
