import Foundation

/// Whether Agent Notch may touch Codex at all — its own files, or its app server.
///
/// # Why one gate
/// Codex data reaches Agent Notch through five doors: the hook, the rollout question monitor, the
/// usage fetch (app server plus rollout files), the daily-cost scan, and the transcript reads
/// behind session detail. The Settings switch promises one thing — "may this app touch my agent" —
/// so all five have to answer to one flag. Gated door by door at each call site, the next reader
/// added would quietly not be gated, and the switch would go back to lying.
///
/// The hook is not gated here: it is Codex calling us, and it stops because the switch removes the
/// hook entries from `hooks.json`. A Codex process already running keeps calling the command it
/// loaded at startup until it restarts, which no flag here can change.
///
/// # Why a global
/// The readers are static functions on value types, called from actors, detached tasks, and the
/// MainActor alike; threading a policy object through all of them would spread the switch across
/// the whole call graph. The app pushes the setting in (`CodexAccessCoordinator`), Core only reads
/// it, and the default is permissive so a target that never sets it behaves as before.
public enum CodexAccess {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var enabled = true

    /// Whether Codex's files and app server may be read right now.
    public static var isAllowed: Bool {
        lock.withLock { enabled }
    }

    /// Applies the user's setting. Called by the app target; Core never sets this itself.
    public static func setAllowed(_ allowed: Bool) {
        lock.withLock { enabled = allowed }
    }

    /// Whether a transcript at `path` may be read.
    ///
    /// Codex ownership is decided by the path, not by the file's contents: `CodexTranscriptReader`
    /// identifies a rollout by reading its first line, and while the switch is off, opening the
    /// file to find out what it is would already be the thing the user turned off.
    public static func allowsTranscript(at path: String) -> Bool {
        isAllowed || !isCodexOwned(path: path)
    }

    /// Files under Codex's own directory. `~/.codex/sessions/**/rollout-*.jsonl` in practice; the
    /// check is the directory rather than the file name so a Codex layout change cannot slip past.
    static func isCodexOwned(path: String) -> Bool {
        path.contains("/.codex/")
    }
}
