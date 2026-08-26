import AgentNotchCore

/// Mapping from SessionStatus / UnifiedSession to `Glyph.State`. Lives in the UI layer.
extension SessionStatus {
    var glyphState: Glyph.State {
        switch self {
        case .starting, .idle, .completed: .standby
        case .thinking, .compacting: .thinking
        case .toolRunning: .working
        // The running subagent count is applied on the UnifiedSession side. The status alone
        // cannot know it, so fall back to a swarm of at least 1.
        case .subagentRunning: .swarm(active: 1)
        case .permissionWaiting: .alert
        case .error: .fault
        case .done: .complete
        }
    }
}

extension UnifiedSession {
    /// While subagents are running, the parent session's (or the subagents' own)
    /// PreToolUse/PostToolUse flip the status between toolRunning and thinking constantly, so
    /// the swarm is held based on `runningSubagentCount` rather than the status.
    /// Interrupting states (awaiting permission, error, done) take priority over the swarm.
    var glyphState: Glyph.State {
        // Restored statuses are historical, and inactive processes cannot still be working.
        // Keep both visually at standby until a fresh hook event confirms the runtime.
        guard presence == .live else { return .standby }

        switch status {
        case .permissionWaiting:
            switch currentInterruption {
            case .permission(let permission):
                // The plan-mode exit confirmation (ExitPlanMode) gets its own figure,
                // distinct from a normal alert.
                return permission.isPlanReview ? .planReview : .alert
            case .question:
                return .question
            case nil:
                return .alert
            }
        case .error, .done, .completed:
            return status.glyphState
        default:
            if runningSubagentCount > 0 {
                return .swarm(active: runningSubagentCount)
            }
            return status.glyphState
        }
    }
}
