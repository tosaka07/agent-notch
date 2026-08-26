import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Claude desktop session locator")
struct ClaudeDesktopSessionLocatorTests {
    @Test("A CLI session resolves to the desktop identifier recorded beside it")
    func resolvesRecordedSession() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            record: [
                "sessionId": "local_8bc26bcd-6e8d-40f5-bf61-bded302e785e",
                "cliSessionId": "dcce9831-fd6d-4a46-9b97-5a4e739d162c",
                "lastActivityAt": 1_785_307_145_807,
            ],
            named: "local_8bc26bcd-6e8d-40f5-bf61-bded302e785e.json",
            in: root
        )

        let resolved = ClaudeDesktopSessionLocator.desktopSessionId(
            forCliSessionId: "dcce9831-fd6d-4a46-9b97-5a4e739d162c",
            in: root
        )

        #expect(resolved == "local_8bc26bcd-6e8d-40f5-bf61-bded302e785e")
    }

    @Test("An unrecorded CLI session — a terminal run — resolves to nothing")
    func unrecordedSession() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            record: [
                "sessionId": "local_1",
                "cliSessionId": "desktop-owned",
            ],
            named: "local_1.json",
            in: root
        )

        #expect(
            ClaudeDesktopSessionLocator.desktopSessionId(
                forCliSessionId: "terminal-only",
                in: root
            ) == nil
        )
        #expect(ClaudeDesktopSessionLocator.desktopSessionId(forCliSessionId: "", in: root) == nil)
    }

    @Test("A missing sessions directory resolves to nothing instead of failing")
    func missingDirectory() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-absent-\(UUID().uuidString)")

        #expect(ClaudeDesktopSessionLocator.desktopSessionId(forCliSessionId: "any", in: root) == nil)
        #expect(ClaudeDesktopSessionLocator.desktopSessionIds(in: root).isEmpty)
    }

    @Test("When two records claim the same CLI session, the most recently active one wins")
    func duplicateRecordsPreferTheNewest() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            record: ["sessionId": "local_old", "cliSessionId": "shared", "lastActivityAt": 1_000],
            named: "local_old.json",
            in: root
        )
        try write(
            record: ["sessionId": "local_new", "cliSessionId": "shared", "lastActivityAt": 2_000],
            named: "local_new.json",
            in: root
        )

        #expect(
            ClaudeDesktopSessionLocator.desktopSessionId(forCliSessionId: "shared", in: root)
                == "local_new"
        )
        #expect(ClaudeDesktopSessionLocator.desktopSessionIds(in: root)["shared"] == "local_new")
    }

    @Test("Records missing a session ID fall back to their file name")
    func sessionIdFallsBackToFileName() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            record: ["cliSessionId": "cli-1"],
            named: "local_from-name.json",
            in: root
        )

        #expect(
            ClaudeDesktopSessionLocator.desktopSessionId(forCliSessionId: "cli-1", in: root)
                == "local_from-name"
        )
    }

    @Test("Unreadable and unrelated files are skipped rather than aborting the walk")
    func malformedRecordsAreSkipped() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let accountDirectory =
            root
            .appendingPathComponent("organization")
            .appendingPathComponent("account")
        try "not json".write(
            to: accountDirectory.appendingPathComponent("local_broken.json"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored".write(
            to: accountDirectory.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try write(
            record: ["sessionId": "local_good", "cliSessionId": "cli-1"],
            named: "local_good.json",
            in: root
        )

        #expect(ClaudeDesktopSessionLocator.desktopSessionIds(in: root) == ["cli-1": "local_good"])
    }

    @Test("Every account directory is scanned, since neither level is predictable")
    func scansEveryAccountDirectory() throws {
        let root = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            record: ["sessionId": "local_a", "cliSessionId": "cli-a"],
            named: "local_a.json",
            in: root
        )
        let otherAccount =
            root
            .appendingPathComponent("other-organization")
            .appendingPathComponent("other-account")
        try FileManager.default.createDirectory(at: otherAccount, withIntermediateDirectories: true)
        try JSONSerialization
            .data(withJSONObject: ["sessionId": "local_b", "cliSessionId": "cli-b"])
            .write(to: otherAccount.appendingPathComponent("local_b.json"))

        #expect(
            ClaudeDesktopSessionLocator.desktopSessionIds(in: root)
                == ["cli-a": "local_a", "cli-b": "local_b"]
        )
    }

    // MARK: - Helpers

    /// Mirrors the app's own layout: `<root>/<organization>/<account>/local_<uuid>.json`.
    private func makeSessionsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-desktop-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("organization").appendingPathComponent("account"),
            withIntermediateDirectories: true
        )
        return root
    }

    private func write(record: [String: Any], named name: String, in root: URL) throws {
        let url =
            root
            .appendingPathComponent("organization")
            .appendingPathComponent("account")
            .appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: record).write(to: url)
    }
}
