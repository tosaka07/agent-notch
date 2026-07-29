import AgentNotchCore
import Foundation

/// Resolves which Claude desktop session, if any, owns a Claude Code session.
///
/// Kept apart from `TerminalInfoResolver` because the two answer different questions from different
/// evidence: a terminal destination comes from the live process tree, a desktop destination from the
/// app's on-disk session records.
@MainActor
enum ClaudeDesktopSessionResolver {
    typealias ResolveOne = @Sendable (String) -> String?
    typealias ResolveAll = @Sendable () -> [String: String]

    /// The desktop app writes its session record asynchronously, so the CLI session ID is not there
    /// yet when the first hook of a fresh session arrives. A few spaced attempts cover that gap
    /// without leaving a lookup that repeats for the session's whole lifetime.
    static let attemptLimit = 3
    static let retryDelay: Duration = .seconds(2)

    /// Resolves every restored Claude Code session from one directory walk.
    ///
    /// Sessions restored at launch get no further hook events if their run already finished, so they
    /// would never reach `resolveIfNeeded`. Their records are already on disk, which is also why
    /// this path does not retry.
    @discardableResult
    static func resolveRestoredSessions(
        manager: SessionManager,
        resolveAll: @escaping ResolveAll = { ClaudeDesktopSessionLocator.desktopSessionIds() }
    ) -> Task<Void, Never>? {
        let sessionIds = manager.allSessions
            .filter { $0.agentType == .claudeCode && !$0.claudeDesktopSessionResolved }
            .map(\.id)
        guard !sessionIds.isEmpty else { return nil }

        for id in sessionIds {
            manager.session(for: id)?.claudeDesktopSessionResolved = true
        }

        return Task { @MainActor in
            let index = await Task.detached { resolveAll() }.value
            var changed = false
            for id in sessionIds {
                guard let session = manager.session(for: id),
                    let desktopSessionId = index[id]
                else { continue }
                session.claudeDesktopSessionId = desktopSessionId
                changed = true
            }
            if changed { manager.notifyChange() }
        }
    }

    /// Schedules one resolution for a session and returns its task for deterministic tests.
    ///
    /// The attempted flag is raised before the work starts: hooks arrive many times per turn, and
    /// the retries belong to this task rather than to a queue of duplicates.
    @discardableResult
    static func resolveIfNeeded(
        session: UnifiedSession,
        sessionId: String,
        manager: SessionManager,
        resolve: @escaping ResolveOne = {
            ClaudeDesktopSessionLocator.desktopSessionId(forCliSessionId: $0)
        },
        retryDelay: Duration = retryDelay
    ) -> Task<Void, Never>? {
        guard session.agentType == .claudeCode, !session.claudeDesktopSessionResolved else {
            return nil
        }
        session.claudeDesktopSessionResolved = true

        return Task { @MainActor in
            for attempt in 0..<attemptLimit {
                if attempt > 0 {
                    try? await Task.sleep(for: retryDelay)
                }
                let desktopSessionId = await Task.detached { resolve(sessionId) }.value
                guard let current = manager.session(for: sessionId) else { return }
                guard let desktopSessionId else { continue }

                current.claudeDesktopSessionId = desktopSessionId
                manager.notifyChange()
                return
            }
        }
    }
}
