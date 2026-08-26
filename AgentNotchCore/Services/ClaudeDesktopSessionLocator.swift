import Foundation

/// Maps a Claude Code CLI session onto the session record the Claude desktop app keeps for it.
///
/// The desktop app runs Claude Code as a child process, so its sessions reach Agent Notch through
/// the same hooks as terminal ones. Addressing such a session in the app needs a *different*
/// identifier: the app mints its own `local_<uuid>` and stores the CLI `session_id` next to it as
/// `cliSessionId`. Only the app-side identifier can open the session, so the mapping has to be read
/// back from the app's own records.
///
/// This also explains why a desktop session cannot be recognised from its PID or TTY: it has no
/// controlling terminal, and its parent chain leads to Electron rather than to anything that can be
/// activated as a destination. Presence of a record is the signal.
public enum ClaudeDesktopSessionLocator {
    /// `~/Library/Application Support/Claude/claude-code-sessions`
    public static var defaultSessionsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// The desktop session ID owning `cliSessionId`, or nil when no record claims it.
    ///
    /// A CLI session can appear in more than one record — importing an already-imported transcript
    /// leaves the older copy in place — so the most recently active record wins. That is the one
    /// the user last looked at, and therefore the one they mean by "go to this session".
    public static func desktopSessionId(
        forCliSessionId cliSessionId: String,
        in root: URL = defaultSessionsDirectory
    ) -> String? {
        guard !cliSessionId.isEmpty else { return nil }

        var best: Record?
        for url in recordURLs(in: root) {
            guard let record = record(at: url), record.cliSessionId == cliSessionId else { continue }
            if let current = best, current.lastActivityAt >= record.lastActivityAt { continue }
            best = record
        }
        return best?.sessionId
    }

    /// Every `cliSessionId` → desktop session ID pair currently on disk.
    ///
    /// Resolving a batch of sessions (app launch restores several at once) walks the directory once
    /// instead of once per session.
    public static func desktopSessionIds(
        in root: URL = defaultSessionsDirectory
    ) -> [String: String] {
        var newest: [String: Record] = [:]
        for url in recordURLs(in: root) {
            guard let record = record(at: url) else { continue }
            if let current = newest[record.cliSessionId],
                current.lastActivityAt >= record.lastActivityAt
            {
                continue
            }
            newest[record.cliSessionId] = record
        }
        return newest.mapValues(\.sessionId)
    }

    // MARK: - Records

    private struct Record {
        let sessionId: String
        let cliSessionId: String
        /// Epoch milliseconds, as the app writes it. Missing values sort oldest.
        let lastActivityAt: Double
    }

    /// Records live at `<root>/<organization>/<account>/local_<uuid>.json`. Both directory levels
    /// are account state Agent Notch cannot predict, so the two levels are enumerated rather than
    /// composed. Each file is a few hundred bytes of session metadata — the transcript itself stays
    /// in `~/.claude/projects`.
    private static func recordURLs(in root: URL) -> [URL] {
        let fileManager = FileManager.default
        return directories(in: root, using: fileManager)
            .flatMap { directories(in: $0, using: fileManager) }
            .flatMap { accountDirectory in
                (try? fileManager.contentsOfDirectory(
                    at: accountDirectory,
                    includingPropertiesForKeys: nil
                )) ?? []
            }
            .filter { $0.pathExtension == "json" }
    }

    private static func directories(in url: URL, using fileManager: FileManager) -> [URL] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? []
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func record(at url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cliSessionId = json["cliSessionId"] as? String,
            !cliSessionId.isEmpty
        else {
            return nil
        }

        // The file name carries the same value as `sessionId`, but the stored field is what the app
        // itself routes on; fall back to the name only when the field is missing.
        let sessionId = (json["sessionId"] as? String) ?? url.deletingPathExtension().lastPathComponent
        guard !sessionId.isEmpty else { return nil }

        return Record(
            sessionId: sessionId,
            cliSessionId: cliSessionId,
            lastActivityAt: (json["lastActivityAt"] as? Double) ?? 0
        )
    }
}
