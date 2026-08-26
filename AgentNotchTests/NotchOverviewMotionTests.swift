import CoreGraphics
import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Notch overview motion")
struct NotchOverviewMotionTests {
    @Test("Compact keeps both wings in place and the expanded page staged above")
    func compactEndpoint() {
        let motion = NotchOverviewMotion(expansion: 0)

        #expect(motion.leadingWingOffset == 0)
        #expect(motion.trailingWingOffset == 0)
        #expect(motion.compactOpacity == 1)
        #expect(motion.runsCompactAnimation)
        #expect(motion.expandedOpacity == 0)
        #expect(motion.expandedOffsetY == -8)
    }

    @Test("Expanded sends the wings outward symmetrically and settles the list")
    func expandedEndpoint() {
        let motion = NotchOverviewMotion(expansion: 1)

        #expect(motion.leadingWingOffset == -18)
        #expect(motion.trailingWingOffset == 18)
        #expect(motion.compactOpacity == 0)
        #expect(!motion.runsCompactAnimation)
        #expect(motion.expandedOpacity == 1)
        #expect(motion.expandedOffsetY == 0)
    }

    @Test("Interrupted motion stays bounded and keeps opposite wing directions")
    func interruptedMotion() {
        let motion = NotchOverviewMotion(expansion: 0.5)

        #expect(motion.leadingWingOffset == -9)
        #expect(motion.trailingWingOffset == 9)
        #expect(motion.compactOpacity == 0.5)
        #expect(motion.runsCompactAnimation)
        #expect(motion.expandedOpacity == 0.5)
        #expect(motion.expandedOffsetY == -4)
        #expect(
            abs(motion.leadingWingOffset + motion.trailingWingOffset)
                < CGFloat.ulpOfOne
        )
    }

    @Test("Spring samples outside the endpoints cannot leak invalid opacity")
    func clampsOvershoot() {
        let beforeCompact = NotchOverviewMotion(expansion: -0.2)
        let beyondExpanded = NotchOverviewMotion(expansion: 1.2)

        #expect(beforeCompact == NotchOverviewMotion(expansion: 0))
        #expect(beyondExpanded == NotchOverviewMotion(expansion: 1))
    }

    @Test("Only overview modes participate in the retained identity host")
    func targets() {
        #expect(NotchOverviewTarget(mode: .compact) == .compact)
        #expect(NotchOverviewTarget(mode: .notification) == .compact)
        #expect(NotchOverviewTarget(mode: .expanded) == .expanded)
        #expect(NotchOverviewTarget(mode: .sessionDetail(sessionId: "s")) == nil)
        #expect(NotchOverviewTarget(mode: .usage) == nil)
    }

    @Test("Compact chrome keeps its width when the expanded page is mounted")
    @MainActor
    func compactWidthIsModeIndependent() {
        let viewModel = NotchViewModel(
            notchSize: CGSize(width: 224, height: 38),
            initialMode: .compact
        )
        let compactWidth = viewModel.compactPresentationWidth

        viewModel.mode = .expanded

        #expect(viewModel.compactPresentationWidth == compactWidth)
        #expect(viewModel.notchWidth == 520)
        #expect(viewModel.notchHeight == 380)
    }

    @Test("A new interruption cannot replace the card already being answered")
    @MainActor
    func incomingInterruptionDoesNotStealVisibleDetail() {
        let manager = SessionManager()
        let visible = manager.getOrCreateSession(id: "visible", agentType: .claudeCode)
        visible.pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "question", questions: [])
        )
        let incoming = manager.getOrCreateSession(id: "incoming", agentType: .claudeCode)
        incoming.pendingInterruptions.enqueue(
            PermissionRequest(
                id: "permission", agentType: .claudeCode, sessionId: incoming.id,
                toolName: "Bash", toolInput: [:], toolUseId: "permission",
                timestamp: Date(), canRespond: true
            )
        )
        let viewModel = NotchViewModel(initialMode: .sessionDetail(sessionId: visible.id))

        viewModel.showIncomingInterruption(incoming.id, sessionManager: manager)

        #expect(viewModel.mode == .sessionDetail(sessionId: visible.id))
    }

    @Test("The oldest queue head across sessions is selected next")
    @MainActor
    func selectsOldestPendingSession() {
        let manager = SessionManager()
        let older = manager.getOrCreateSession(id: "older", agentType: .claudeCode)
        let newer = manager.getOrCreateSession(id: "newer", agentType: .claudeCode)
        let start = Date(timeIntervalSince1970: 100)
        older.pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "question", questions: [], receivedAt: start)
        )
        newer.pendingInterruptions.enqueue(
            PermissionRequest(
                id: "permission", agentType: .claudeCode, sessionId: newer.id,
                toolName: "Bash", toolInput: [:], toolUseId: "permission",
                timestamp: start.addingTimeInterval(1), canRespond: true
            )
        )

        #expect(manager.nextPendingInterruptionSession()?.id == older.id)

        let viewModel = NotchViewModel(initialMode: .compact)
        viewModel.showIncomingInterruption(newer.id, sessionManager: manager)
        #expect(viewModel.mode == .sessionDetail(sessionId: older.id))

        older.pendingInterruptions.remove(kind: .question, toolUseId: "question")
        #expect(manager.nextPendingInterruptionSession()?.id == newer.id)
    }

    @Test("Global ordering is preserved while one session has multiple queued items")
    @MainActor
    func preservesGlobalOrderAcrossSessionHeads() {
        let manager = SessionManager()
        let firstSession = manager.getOrCreateSession(id: "first", agentType: .claudeCode)
        let secondSession = manager.getOrCreateSession(id: "second", agentType: .codex)
        let start = Date(timeIntervalSince1970: 100)
        firstSession.pendingInterruptions.enqueue(
            PendingQuestion(toolUseId: "a1", questions: [], receivedAt: start)
        )
        firstSession.pendingInterruptions.enqueue(
            PendingQuestion(
                toolUseId: "a2",
                questions: [],
                receivedAt: start.addingTimeInterval(2)
            )
        )
        secondSession.pendingInterruptions.enqueue(
            PendingQuestion(
                toolUseId: "b1",
                questions: [],
                receivedAt: start.addingTimeInterval(1)
            )
        )

        #expect(manager.nextPendingInterruptionSession()?.currentInterruption?.id == "question:a1")
        firstSession.pendingInterruptions.remove(kind: .question, toolUseId: "a1")
        #expect(manager.nextPendingInterruptionSession()?.currentInterruption?.id == "question:b1")
        secondSession.pendingInterruptions.remove(kind: .question, toolUseId: "b1")
        #expect(manager.nextPendingInterruptionSession()?.currentInterruption?.id == "question:a2")
    }
}
