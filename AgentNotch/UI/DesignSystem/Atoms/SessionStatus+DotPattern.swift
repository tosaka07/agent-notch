import AgentNotchCore

/// SessionStatus → DotPattern のマッピング。UI 層に置く（DotPattern は UI 依存）。
extension SessionStatus {
    var dotPattern: DotPattern {
        switch self {
        case .starting, .idle, .completed:
            return .standby
        case .thinking, .compacting:
            return .thinking
        case .toolRunning, .subagentRunning:
            return .working
        case .permissionWaiting:
            return .alert
        case .error:
            return .fault
        case .done:
            return .complete
        }
    }
}
