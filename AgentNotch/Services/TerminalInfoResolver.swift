import AgentNotchCore
import Foundation

/// Revalidates the terminal destination represented by a session's current PID/TTY.
///
/// A persisted app name is display history, not proof that the destination still exists. This
/// module clears that history before resolving and exposes the action only when resolution
/// succeeds for the same runtime metadata.
@MainActor
enum TerminalInfoResolver {
    typealias Resolve =
        @MainActor @Sendable (
            _ pid: Int32?,
            _ tty: String?
        ) -> TerminalJumper.TerminalInfo?

    /// Revalidates every restored session after the startup process-presence sweep.
    @discardableResult
    static func resolveRestoredSessions(
        manager: SessionManager,
        resolve: @escaping Resolve = TerminalJumper.resolveTerminalInfo
    ) -> [Task<Void, Never>] {
        manager.allSessions
            .filter { $0.presence == .restored }
            .compactMap {
                resolveIfNeeded(
                    session: $0,
                    sessionId: $0.id,
                    manager: manager,
                    resolve: resolve
                )
            }
    }

    /// Schedules one resolution attempt and returns its task for deterministic tests.
    @discardableResult
    static func resolveIfNeeded(
        session: UnifiedSession,
        sessionId: String,
        manager: SessionManager,
        resolve: @escaping Resolve = TerminalJumper.resolveTerminalInfo
    ) -> Task<Void, Never>? {
        guard !session.terminalInfoResolved, session.pid != nil || session.tty != nil else {
            return nil
        }

        let pid = session.pid
        let tty = session.tty
        session.terminalInfoResolved = true
        session.terminalAppName = nil
        session.terminalAppIcon = nil
        session.tmuxPaneTarget = nil
        session.herdrPaneTarget = nil
        manager.notifyChange()

        return Task { @MainActor in
            let info = resolve(pid, tty)
            guard let current = manager.session(for: sessionId),
                current.pid == pid,
                current.tty == tty,
                current.presence != .inactive
            else {
                return
            }

            current.terminalAppName = info?.appName
            current.terminalAppIcon = info?.appIcon
            current.tmuxPaneTarget = info?.tmuxTarget
            current.herdrPaneTarget = info?.herdrPaneTarget
            manager.notifyChange()
        }
    }
}
