import AgentNotchCore

/// SessionStatus → DotPattern のマッピング。UI 層に置く（DotPattern は UI 依存）。
extension SessionStatus {
    var dotPattern: DotPattern {
        switch self {
        case .starting, .idle, .completed:
            return .standby
        case .thinking, .compacting:
            return .thinking
        case .toolRunning:
            return .working
        case .subagentRunning:
            // 実行中 subagent 数は UnifiedSession.dotPattern 側で反映する。
            // status 単体からは分からないため、最低 1 の swarm にフォールバックする。
            return .swarm(active: 1)
        case .permissionWaiting:
            return .alert
        case .error:
            return .fault
        case .done:
            return .complete
        }
    }
}

/// UnifiedSession → DotPattern のマッピング。
///
/// subagent 実行中は親セッション（や subagent 自身）の PreToolUse/PostToolUse で
/// status が toolRunning/thinking に頻繁に切り替わるため、status ではなく
/// `runningSubagentCount` を見て swarm を維持する。
/// 割り込み系（permission 待ち・エラー・完了）は swarm より優先して表示する。
extension UnifiedSession {
    var dotPattern: DotPattern {
        switch status {
        case .permissionWaiting, .error, .done, .completed:
            return status.dotPattern
        default:
            if runningSubagentCount > 0 {
                return .swarm(active: runningSubagentCount)
            }
            return status.dotPattern
        }
    }
}
