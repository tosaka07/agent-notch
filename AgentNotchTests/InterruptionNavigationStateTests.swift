import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Interruption navigation state")
struct InterruptionNavigationStateTests {
    @Test("An asynchronous answer advances only after its queue item resolves")
    func asynchronousAnswerWaitsForResolution() {
        var state = InterruptionNavigationState()
        state.beginResolution(of: "question:first", fallback: .back)

        #expect(
            state.navigationAfterQueueChange(
                queuedInterruptions: [question("first"), question("second")],
                nextSessionId: "current",
                currentSessionId: "current"
            ) == nil
        )
        #expect(state.isResolving("question:first"))

        #expect(
            state.navigationAfterQueueChange(
                queuedInterruptions: [question("second")],
                nextSessionId: "next",
                currentSessionId: "current"
            ) == .showSession("next")
        )
        #expect(!state.hasPendingResolution)
    }

    @Test("A second response cannot replace the resolution already in flight")
    func inFlightResolutionCannotBeReplaced() {
        var state = InterruptionNavigationState()
        let beganFirst = state.beginResolution(of: "question:first", fallback: .back)

        let beganSecond = state.beginResolution(of: "permission:second", fallback: .close)

        #expect(beganFirst)
        #expect(!beganSecond)
        #expect(state.isResolving("question:first"))
        #expect(!state.isResolving("permission:second"))
    }

    @Test("A transport alias change does not look like a completed answer")
    func aliasChangeKeepsResolutionInFlight() {
        var state = InterruptionNavigationState()
        state.beginResolution(of: "question:observation", fallback: .back)
        let upgraded = PendingQuestion(
            toolUseId: "response-channel",
            questions: [],
            correlationToolUseIds: ["observation", "response-channel"]
        )

        #expect(
            state.navigationAfterQueueChange(
                queuedInterruptions: [.question(upgraded)],
                nextSessionId: "next",
                currentSessionId: "current"
            ) == nil
        )
        #expect(state.isResolving("question:observation"))
    }

    @Test("Resolving the head reveals the next item in the same session")
    func sameSessionQueueAdvancesInPlace() {
        var state = InterruptionNavigationState()
        state.beginResolution(of: "question:first", fallback: .back)

        let navigation = state.navigationAfterQueueChange(
            queuedInterruptions: [question("second")],
            nextSessionId: "current",
            currentSessionId: "current"
        )

        #expect(navigation == nil)
        #expect(!state.hasPendingResolution)
    }

    @Test("The final resolution uses the action-specific fallback")
    func finalResolutionUsesFallback() {
        var permissionState = InterruptionNavigationState()
        permissionState.beginResolution(of: "permission:only", fallback: .close)
        let afterPermission = permissionState.navigationAfterQueueChange(
            queuedInterruptions: [],
            nextSessionId: nil,
            currentSessionId: "current"
        )

        var questionState = InterruptionNavigationState()
        questionState.beginResolution(of: "question:only", fallback: .back)
        let afterQuestion = questionState.navigationAfterQueueChange(
            queuedInterruptions: [],
            nextSessionId: nil,
            currentSessionId: "current"
        )

        #expect(afterPermission == .close)
        #expect(afterQuestion == .back)
    }

    @Test("Leaving for the terminal closes without waiting for queue resolution")
    func terminalHandoffClosesImmediately() {
        var state = InterruptionNavigationState()
        state.beginResolution(of: "question:only", fallback: .back)

        let navigation = state.leaveForTerminal()

        #expect(navigation == .close)
        #expect(!state.hasPendingResolution)
    }

    @Test("Queue changes are ignored when no notch response is in flight")
    func queueChangeWithoutResponseIsIgnored() {
        var state = InterruptionNavigationState()

        let navigation = state.navigationAfterQueueChange(
            queuedInterruptions: [],
            nextSessionId: "next",
            currentSessionId: "current"
        )

        #expect(navigation == nil)
    }

    @Test("The same raw tool id in another interruption kind is not a match")
    func interruptionKindIsPartOfResolutionIdentity() {
        var state = InterruptionNavigationState()
        state.beginResolution(of: "question:shared", fallback: .back)

        let navigation = state.navigationAfterQueueChange(
            queuedInterruptions: [permission("shared")],
            nextSessionId: nil,
            currentSessionId: "current"
        )

        #expect(navigation == .back)
        #expect(!state.hasPendingResolution)
    }

    private func question(_ id: String) -> PendingInterruption {
        .question(PendingQuestion(toolUseId: id, questions: []))
    }

    private func permission(_ id: String) -> PendingInterruption {
        .permission(
            PermissionRequest(
                id: id,
                agentType: .claudeCode,
                sessionId: "session",
                toolName: "Bash",
                toolInput: [:],
                toolUseId: id,
                timestamp: .now,
                canRespond: true
            )
        )
    }
}
