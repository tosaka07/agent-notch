import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Claude desktop session resolution")
@MainActor
struct ClaudeDesktopSessionResolverTests {
    @Test("A recorded session gains the desktop identifier it is addressed by")
    func recordedSessionResolves() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "cli-1", agentType: .claudeCode)

        let pendingTask = ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { cliSessionId in
                cliSessionId == "cli-1" ? "local_1" : nil
            },
            retryDelay: .zero
        )
        let task = try #require(pendingTask)
        await task.value

        #expect(session.claudeDesktopSessionResolved)
        #expect(session.claudeDesktopSessionId == "local_1")
    }

    @Test("A record written after the session's first hook is still picked up")
    func lateRecordIsRetried() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "cli-1", agentType: .claudeCode)
        let attempts = Attempts()

        let pendingTask = ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _ in attempts.next() >= 2 ? "local_1" : nil },
            retryDelay: .zero
        )
        let task = try #require(pendingTask)
        await task.value

        #expect(session.claudeDesktopSessionId == "local_1")
        #expect(attempts.count == 2)
    }

    @Test("A terminal session stops being looked up after a bounded number of attempts")
    func unrecordedSessionGivesUp() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "cli-1", agentType: .claudeCode)
        let attempts = Attempts()

        let pendingTask = ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _ in
                _ = attempts.next()
                return nil
            },
            retryDelay: .zero
        )
        let task = try #require(pendingTask)
        await task.value

        #expect(session.claudeDesktopSessionId == nil)
        #expect(attempts.count == ClaudeDesktopSessionResolver.attemptLimit)
    }

    @Test("Hooks arriving during resolution do not queue duplicate lookups")
    func alreadyAttemptedSessionIsNotLookedUpAgain() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "cli-1", agentType: .claudeCode)

        let firstTask = ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _ in "local_1" },
            retryDelay: .zero
        )
        let secondTask = ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _ in "local_2" },
            retryDelay: .zero
        )
        let task = try #require(firstTask)
        await task.value

        #expect(secondTask == nil)
        #expect(session.claudeDesktopSessionId == "local_1")
    }

    @Test("Codex sessions are never looked up in Claude's records")
    func codexSessionIsSkipped() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)

        let pendingTask = ClaudeDesktopSessionResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _ in "local_1" },
            retryDelay: .zero
        )

        #expect(pendingTask == nil)
        #expect(session.claudeDesktopSessionResolved == false)
    }

    @Test("Restored sessions resolve from a single directory walk")
    func restoredSessionsResolveTogether() async throws {
        let manager = SessionManager()
        let desktopRun = UnifiedSession(id: "cli-desktop", agentType: .claudeCode)
        let terminalRun = UnifiedSession(id: "cli-terminal", agentType: .claudeCode)
        let codexRun = UnifiedSession(id: "thread-1", agentType: .codex)
        manager.restoreSessions(
            from: [desktopRun, terminalRun, codexRun].map(SessionSnapshot.init)
        )
        let walks = Attempts()

        let pendingTask = ClaudeDesktopSessionResolver.resolveRestoredSessions(
            manager: manager,
            resolveAll: {
                _ = walks.next()
                return ["cli-desktop": "local_desktop"]
            }
        )
        let task = try #require(pendingTask)
        await task.value

        #expect(walks.count == 1)
        #expect(manager.session(for: "cli-desktop")?.claudeDesktopSessionId == "local_desktop")
        #expect(manager.session(for: "cli-terminal")?.claudeDesktopSessionId == nil)
        #expect(manager.session(for: "cli-terminal")?.claudeDesktopSessionResolved == true)
        #expect(manager.session(for: "thread-1")?.claudeDesktopSessionResolved == false)
    }

    /// Counts lookups from the detached executor the resolver runs them on.
    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0

        var count: Int {
            lock.withLock { attempts }
        }

        /// Returns the number of this attempt, starting at 1.
        func next() -> Int {
            lock.withLock {
                attempts += 1
                return attempts
            }
        }
    }
}
