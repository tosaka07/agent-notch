import AgentNotchCore

/// Navigation state for a response initiated inside the notch.
///
/// The response transport may resolve synchronously (Claude permissions) or
/// asynchronously (Codex questions). Navigation is therefore driven by the
/// original queue item's disappearance, never by the submit button itself.
struct InterruptionNavigationState {
    enum Fallback: Equatable {
        case close
        case back
    }

    enum Navigation: Equatable {
        case showSession(String)
        case close
        case back
    }

    private struct PendingResolution {
        let interruptionId: String
        let fallback: Fallback
    }

    private var pendingResolution: PendingResolution?

    var hasPendingResolution: Bool {
        pendingResolution != nil
    }

    func isResolving(_ interruptionId: String) -> Bool {
        pendingResolution?.interruptionId == interruptionId
    }

    @discardableResult
    mutating func beginResolution(
        of interruptionId: String,
        fallback: Fallback
    ) -> Bool {
        guard pendingResolution == nil else { return false }
        pendingResolution = PendingResolution(
            interruptionId: interruptionId,
            fallback: fallback
        )
        return true
    }

    mutating func navigationAfterQueueChange(
        queuedInterruptions: [PendingInterruption],
        nextSessionId: String?,
        currentSessionId: String
    ) -> Navigation? {
        guard let pendingResolution else { return nil }
        guard
            !queuedInterruptions.contains(where: {
                matches($0, interruptionId: pendingResolution.interruptionId)
            })
        else {
            return nil
        }

        self.pendingResolution = nil
        if let nextSessionId {
            return nextSessionId == currentSessionId
                ? nil
                : .showSession(nextSessionId)
        }

        switch pendingResolution.fallback {
        case .close: return .close
        case .back: return .back
        }
    }

    private func matches(
        _ interruption: PendingInterruption,
        interruptionId: String
    ) -> Bool {
        if interruption.id == interruptionId {
            return true
        }
        guard case .question(let question) = interruption,
            interruptionId.hasPrefix("question:")
        else {
            return false
        }
        return question.correlationToolUseIds.contains(
            String(interruptionId.dropFirst("question:".count))
        )
    }

    mutating func leaveForTerminal() -> Navigation {
        pendingResolution = nil
        return .close
    }
}
