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
