import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Codex question coordinator")
@MainActor
struct CodexQuestionCoordinatorTests {
    private final class SharedTransport: CodexSharedQuestionTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var submitted: [(CodexRPCID, [String: [String]])] = []
        private var starts = 0
        private var followed = Set<String>()

        var submissionCount: Int { lock.withLock { submitted.count } }
        var lastAnswers: [String: [String]]? { lock.withLock { submitted.last?.1 } }
        var startCount: Int { lock.withLock { starts } }
        var followedIds: Set<String> { lock.withLock { followed } }

        func start() { lock.withLock { starts += 1 } }
        func stop() {}
        func setFollowedThreadIds(_ ids: Set<String>) {
            lock.withLock { followed = ids }
        }
        func submit(requestId: CodexRPCID, answers: [String: [String]]) async throws {
            lock.withLock { submitted.append((requestId, answers)) }
        }
    }

    private final class DesktopTransport: CodexDesktopQuestionTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var followed = Set<String>()
        private var starts = 0

        var followedIds: Set<String> { lock.withLock { followed } }
        var startCount: Int { lock.withLock { starts } }

        func start() { lock.withLock { starts += 1 } }
        func stop() {}
        func setFollowedThreadIds(_ ids: Set<String>) {
            lock.withLock { followed = ids }
        }
        func submit(
            threadId: String,
            requestId: CodexRPCID,
            answers: [String: [String]]
        ) async throws {}
    }

    private final class FailingSharedTransport:
        CodexSharedQuestionTransport, @unchecked Sendable
    {
        struct DeliveryError: Error {}

        func start() {}
        func stop() {}
        func setFollowedThreadIds(_ ids: Set<String>) {}
        func submit(requestId: CodexRPCID, answers: [String: [String]]) async throws {
            throw DeliveryError()
        }
    }

    @Test("Shared daemon client starts before the first CLI session")
    func sharedStartsProactively() {
        let manager = SessionManager()
        let shared = SharedTransport()
        let desktop = DesktopTransport()
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: shared,
            desktopTransport: desktop
        )

        coordinator.start()
        defer { coordinator.stop() }

        #expect(shared.startCount == 1)
        #expect(shared.followedIds.isEmpty)
        #expect(desktop.startCount == 0)
        #expect(desktop.followedIds.isEmpty)
    }

    @Test("Shared App Server request appears, submits by question id, and clears on resolution")
    func sharedRoundTrip() async throws {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let shared = SharedTransport()
        let desktop = DesktopTransport()
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: shared,
            desktopTransport: desktop
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .string("request-1"))
        coordinator.receiveSharedRequest(request)

        let session = try #require(manager.session(for: "thread-1"))
        let pending = try #require(session.pendingQuestion)
        #expect(session.status == .permissionWaiting)
        #expect(pending.questions.first?.responseKey == "target")
        #expect(shared.followedIds == ["thread-1"])
        #expect(desktop.followedIds == ["thread-1"])

        coordinator.answer(
            sessionId: "thread-1",
            toolUseId: pending.toolUseId,
            answers: ["target": ["Staging"]]
        )
        try await waitUntil { shared.submissionCount == 1 }
        #expect(shared.lastAnswers == ["target": ["Staging"]])
        #expect(session.pendingQuestion?.isSubmitting == true)

        coordinator.receiveSharedResolution(
            CodexResolvedUserInput(requestId: .string("request-1"), threadId: "thread-1")
        )
        #expect(session.pendingQuestion == nil)
        #expect(session.status == .thinking)
    }

    @Test("Desktop snapshot removal reflects an answer made in Codex App")
    func desktopExternalResolution() throws {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .integer(7))
        coordinator.receiveDesktopSnapshot(threadId: "thread-1", requests: [request])
        #expect(manager.session(for: "thread-1")?.pendingQuestion != nil)

        coordinator.receiveDesktopSnapshot(threadId: "thread-1", requests: [])
        #expect(manager.session(for: "thread-1")?.pendingQuestion == nil)
        #expect(manager.session(for: "thread-1")?.status == .thinking)
    }

    @Test("A direct resolution remains terminal across duplicate adapter snapshots")
    func directResolutionSuppressesAdapterReplays() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .string("request-1"))
        coordinator.receiveSharedRequest(request)
        #expect(session.pendingInterruptions.questions.map(\.toolUseId) == ["item-1"])

        coordinator.receiveSharedResolution(
            CodexResolvedUserInput(requestId: .string("request-1"), threadId: "thread-1")
        )
        coordinator.receiveDesktopSnapshot(threadId: "thread-1", requests: [request])
        coordinator.receiveSharedRequest(request)

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("A dismissed direct request remains dismissed across adapter snapshots")
    func dismissalSuppressesAdapterReplays() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .string("request-1"))
        coordinator.receiveSharedRequest(request)
        coordinator.dismiss(sessionId: "thread-1", toolUseId: "item-1")
        session.pendingInterruptions.remove(kind: .question, toolUseId: "item-1")
        coordinator.receiveDesktopSnapshot(threadId: "thread-1", requests: [request])

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("A hook-only CLI question is visible but remains terminal-only")
    func hookQuestionIsTerminalOnly() throws {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveHookQuestion(
            AskQuestionInfo(
                sessionId: "thread-1",
                toolUseId: "call-1",
                questions: [makeRequest(id: .integer(1)).questions[0].bannerQuestion]
            ),
            turnId: "turn-1"
        )

        let pending = try #require(manager.session(for: "thread-1")?.pendingQuestion)
        #expect(pending.toolUseId == "call-1")
        #expect(pending.responseMode == .terminalOnly)
        #expect(!coordinator.canHandle(sessionId: "thread-1", toolUseId: "call-1"))
    }

    @Test("A direct request upgrades the observed question without creating a second banner")
    func directRequestUpgradesObservedQuestion() throws {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .string("request-1"))
        var observedQuestion = request.questions[0].bannerQuestion
        // Hook/rollout payloads can omit App Server-only flags. The visible
        // identity is still enough to correlate the request.
        observedQuestion = AskQuestionInfo.Question(
            question: observedQuestion.question,
            header: observedQuestion.header,
            multiSelect: false,
            options: observedQuestion.options,
            responseKey: observedQuestion.responseKey,
            allowsOther: false,
            isSecret: false
        )
        coordinator.receiveHookQuestion(
            AskQuestionInfo(
                sessionId: "thread-1",
                toolUseId: "call-1",
                questions: [observedQuestion]
            ),
            turnId: "turn-1"
        )
        coordinator.receiveSharedRequest(request)

        let pending = try #require(manager.session(for: "thread-1")?.pendingQuestion)
        #expect(pending.toolUseId == "call-1")
        #expect(pending.responseMode == .direct)
        #expect(pending.questions.first?.allowsOther == true)
        #expect(coordinator.canHandle(sessionId: "thread-1", toolUseId: "call-1"))
    }

    @Test("A direct request correlates with its visible queued observation without a turn id")
    func directRequestMatchesQueuedObservationWithoutTurnId() throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(
            id: .string("request-1"),
            itemId: "direct-item"
        )
        coordinator.receiveHookQuestion(
            AskQuestionInfo(
                sessionId: "thread-1",
                toolUseId: "observed-call",
                questions: request.questions.map(\.bannerQuestion)
            ),
            turnId: nil
        )
        coordinator.receiveSharedRequest(request)

        #expect(session.pendingInterruptions.questions.map(\.toolUseId) == ["observed-call"])
        #expect(
            coordinator.canHandle(
                sessionId: session.id,
                toolUseId: "observed-call"
            )
        )
    }

    @Test("An ambiguous direct request does not claim an arbitrary observation")
    func directRequestLeavesAmbiguousObservationsSeparate() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .string("request-1"), itemId: "direct-item")
        let questions = request.questions.map(\.bannerQuestion)
        coordinator.receiveHookQuestion(
            AskQuestionInfo(sessionId: "thread-1", toolUseId: "observed-1", questions: questions),
            turnId: nil
        )
        coordinator.receiveHookQuestion(
            AskQuestionInfo(sessionId: "thread-1", toolUseId: "observed-2", questions: questions),
            turnId: nil
        )
        coordinator.receiveSharedRequest(request)

        #expect(
            session.pendingInterruptions.questions.map(\.toolUseId)
                == ["observed-1", "observed-2", "direct-item"]
        )
        #expect(coordinator.canHandle(sessionId: "thread-1", toolUseId: "direct-item"))
        #expect(!coordinator.canHandle(sessionId: "thread-1", toolUseId: "observed-1"))
        #expect(!coordinator.canHandle(sessionId: "thread-1", toolUseId: "observed-2"))
    }

    @Test("Rollout resolution removes a recovered question")
    func rolloutResolutionClearsRecoveredQuestion() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let request = makeRequest(id: .integer(1))
        let recovered = CodexRolloutQuestion(
            callId: "call-1",
            turnId: "turn-1",
            questions: request.questions.map(\.bannerQuestion),
            autoResolutionMs: nil,
            receivedAt: Date()
        )
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [recovered])
        #expect(manager.session(for: "thread-1")?.pendingQuestion != nil)

        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [])
        #expect(manager.session(for: "thread-1")?.pendingQuestion == nil)
        #expect(manager.session(for: "thread-1")?.status == .thinking)
    }

    @Test("A stale rollout snapshot cannot re-open a resolved observation")
    func resolvedRolloutQuestionIgnoresReplay() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let recovered = CodexRolloutQuestion(
            callId: "call-1",
            turnId: "turn-1",
            questions: makeRequest(id: .integer(1)).questions.map(\.bannerQuestion),
            autoResolutionMs: nil,
            receivedAt: Date()
        )
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [recovered])
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [])
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [recovered])

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("A dismissed rollout question cannot re-open after a stale snapshot")
    func dismissedRolloutQuestionIgnoresReplay() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        let recovered = CodexRolloutQuestion(
            callId: "call-1",
            turnId: "turn-1",
            questions: makeRequest(id: .integer(1)).questions.map(\.bannerQuestion),
            autoResolutionMs: nil,
            receivedAt: Date()
        )
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [recovered])
        coordinator.dismiss(sessionId: "thread-1", toolUseId: "call-1")
        session.pendingInterruptions.remove(kind: .question, toolUseId: "call-1")
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [])
        coordinator.receiveRolloutSnapshot(sessionId: "thread-1", questions: [recovered])

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("A direct delivery failure downgrades to terminal instead of pretending it expired")
    func deliveryFailureDowngrades() async throws {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: FailingSharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveSharedRequest(makeRequest(id: .string("request-1")))
        let pending = try #require(manager.session(for: "thread-1")?.pendingQuestion)
        coordinator.answer(
            sessionId: "thread-1",
            toolUseId: pending.toolUseId,
            answers: ["target": ["Staging"]]
        )

        // `answer` launches its response path on the main actor. Under the full
        // suite's concurrent load, that task can start after the one-second
        // default even though the immediate transport failure is handled
        // correctly.
        try await waitUntil(timeout: .seconds(5)) {
            manager.session(for: "thread-1")?.pendingQuestion?.responseMode == .terminalOnly
        }
        let downgraded = try #require(manager.session(for: "thread-1")?.pendingQuestion)
        #expect(downgraded.phase == .waiting)
        #expect(!downgraded.isExpired)
    }

    @Test("Requests received before the hook session are presented once the session appears")
    func requestWaitsForSession() async throws {
        let manager = SessionManager()
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveSharedRequest(makeRequest(id: .string("early")))
        #expect(manager.session(for: "thread-1") == nil)

        _ = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        try await waitUntil {
            manager.session(for: "thread-1")?.pendingQuestion != nil
        }
    }

    @Test("Concurrent Codex questions stay FIFO and reveal the second after resolution")
    func concurrentQuestionsAreQueued() throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveSharedRequest(
            makeRequest(
                id: .string("request-1"),
                turnId: "turn-1",
                itemId: "item-1",
                question: "First?"
            )
        )
        coordinator.receiveSharedRequest(
            makeRequest(
                id: .string("request-2"),
                turnId: "turn-2",
                itemId: "item-2",
                question: "Second?"
            )
        )

        #expect(session.pendingInterruptions.questions.map(\.toolUseId) == ["item-1", "item-2"])
        #expect(session.currentInterruption?.id == "question:item-1")

        coordinator.receiveSharedResolution(
            CodexResolvedUserInput(requestId: .string("request-1"), threadId: "thread-1")
        )
        #expect(session.currentInterruption?.id == "question:item-2")
    }

    @Test("Concurrent Codex requests with identical text remain separate queue items")
    func identicalConcurrentQuestionsRemainSeparate() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveSharedRequest(
            makeRequest(
                id: .string("request-1"),
                turnId: "turn-1",
                itemId: "item-1",
                question: "Proceed?"
            )
        )
        coordinator.receiveSharedRequest(
            makeRequest(
                id: .string("request-2"),
                turnId: "turn-2",
                itemId: "item-2",
                question: "Proceed?"
            )
        )

        #expect(session.pendingInterruptions.questions.map(\.toolUseId) == ["item-1", "item-2"])
    }

    @Test("An uncorrelated resolution cannot remove one of several queued questions")
    func ambiguousObservedResolutionKeepsQueue() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveSharedRequest(
            makeRequest(
                id: .string("request-1"),
                turnId: "turn-1",
                itemId: "item-1",
                question: "First?"
            )
        )
        coordinator.receiveSharedRequest(
            makeRequest(
                id: .string("request-2"),
                turnId: "turn-2",
                itemId: "item-2",
                question: "Second?"
            )
        )

        coordinator.receiveObservedResolution(
            sessionId: "thread-1",
            toolUseId: "uncorrelated-call"
        )

        #expect(session.pendingInterruptions.questions.map(\.toolUseId) == ["item-1", "item-2"])
    }

    @Test("An observed resolution removes the question with the matching call id")
    func observedResolutionUsesExactCorrelation() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.receiveHookQuestion(
            AskQuestionInfo(
                sessionId: "thread-1",
                toolUseId: "call-1",
                questions: [makeRequest(id: .integer(1)).questions[0].bannerQuestion]
            ),
            turnId: "turn-1"
        )

        coordinator.receiveObservedResolution(
            sessionId: "thread-1",
            toolUseId: "call-1"
        )

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("An uncorrelated resolution can resolve the only live question")
    func uncorrelatedObservedResolutionUsesSingleCandidate() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.receiveSharedRequest(makeRequest(id: .string("request-1")))

        coordinator.receiveObservedResolution(
            sessionId: "thread-1",
            toolUseId: "different-call-id"
        )

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("A resolution received before its request suppresses the stale replay")
    func earlyResolutionSuppressesLateRequest() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveSharedResolution(
            CodexResolvedUserInput(requestId: .string("request-1"), threadId: "thread-1")
        )
        coordinator.receiveSharedRequest(makeRequest(id: .string("request-1")))

        #expect(session.pendingInterruptions.isEmpty)
    }

    @Test("An observed resolution received first suppresses the stale hook replay")
    func earlyObservedResolutionSuppressesLateObservation() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "thread-1", agentType: .codex)
        let coordinator = CodexQuestionCoordinator(
            sessionManager: manager,
            sharedTransport: SharedTransport(),
            desktopTransport: DesktopTransport()
        )
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.receiveObservedResolution(sessionId: "thread-1", toolUseId: "call-1")
        coordinator.receiveHookQuestion(
            AskQuestionInfo(
                sessionId: "thread-1",
                toolUseId: "call-1",
                questions: makeRequest(id: .integer(1)).questions.map(\.bannerQuestion)
            ),
            turnId: "turn-1"
        )

        #expect(session.pendingInterruptions.isEmpty)
    }

    private func makeRequest(
        id: CodexRPCID,
        turnId: String = "turn-1",
        itemId: String = "item-1",
        question: String = "Where?"
    ) -> CodexUserInputRequest {
        CodexUserInputRequest(
            requestId: id,
            threadId: "thread-1",
            turnId: turnId,
            itemId: itemId,
            questions: [
                CodexUserInputRequest.Question(
                    id: "target",
                    header: "Target",
                    question: question,
                    options: [.init(label: "Staging", description: nil)],
                    isOther: true,
                    isSecret: false
                )
            ],
            autoResolutionMs: nil
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
