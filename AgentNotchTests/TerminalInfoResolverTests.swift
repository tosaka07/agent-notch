import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Terminal destination resolution")
@MainActor
struct TerminalInfoResolverTests {
    @Test("A restored session becomes actionable only after its destination is revalidated")
    func restoredSessionIsRevalidated() async throws {
        let manager = SessionManager()
        let source = UnifiedSession(id: "restored-terminal", agentType: .codex)
        source.presence = .live
        source.pid = 12_345
        source.terminalAppName = "Stale Terminal"
        source.terminalInfoResolved = true
        manager.restoreSessions(from: [SessionSnapshot(session: source)])

        let restored = try #require(manager.session(for: source.id))
        #expect(restored.isTerminalJumpAvailable == false)

        let tasks = TerminalInfoResolver.resolveRestoredSessions(
            manager: manager,
            resolve: { pid, tty in
                #expect(pid == 12_345)
                #expect(tty == nil)
                return TerminalJumper.TerminalInfo(
                    appName: "Terminal",
                    appIcon: nil,
                    tmuxTarget: nil
                )
            }
        )
        for task in tasks {
            await task.value
        }

        #expect(restored.terminalInfoResolved)
        #expect(restored.terminalAppName == "Terminal")
        #expect(restored.isTerminalJumpAvailable)
    }

    /// A herdr pane identifier is only as good as the resolution that produced it: the stale one is
    /// dropped before the attempt, and the pane that answered replaces it.
    @Test("A herdr pane target is replaced by the one this resolution confirmed")
    func herdrPaneTargetIsRevalidated() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "herdr-session", agentType: .claudeCode)
        session.presence = .live
        session.pid = 4_242
        session.herdrPaneTarget = "w1:p1"

        let pendingTask = TerminalInfoResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _, _ in
                TerminalJumper.TerminalInfo(
                    appName: "Ghostty",
                    appIcon: nil,
                    tmuxTarget: nil,
                    herdrPaneTarget: "w6:p2"
                )
            }
        )
        let task = try #require(pendingTask)
        await task.value

        #expect(session.herdrPaneTarget == "w6:p2")
        #expect(session.isTerminalJumpAvailable)
    }

    @Test("An unresolved destination never exposes terminal jump")
    func unavailableDestinationStaysHidden() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "missing-terminal", agentType: .claudeCode)
        session.presence = .live
        session.pid = 54_321

        let pendingTask = TerminalInfoResolver.resolveIfNeeded(
            session: session,
            sessionId: session.id,
            manager: manager,
            resolve: { _, _ in nil }
        )
        let task = try #require(pendingTask)
        await task.value

        #expect(session.terminalInfoResolved)
        #expect(session.terminalAppName == nil)
        #expect(session.isTerminalJumpAvailable == false)
    }
}
