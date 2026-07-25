import AgentNotchCore

/// SessionStatus / UnifiedSession → `Glyph.State` のマッピング。UI 層に置く。
///
/// 旧 `DotPattern` からの置き換え。図柄は Claude Design のモック（2a / 4a）に準拠する。
extension SessionStatus {
    var glyphState: Glyph.State {
        switch self {
        case .starting, .idle, .completed: .standby
        case .thinking, .compacting: .thinking
        case .toolRunning: .working
        // 実行中 subagent 数は UnifiedSession 側で反映する。status 単体では分からないため
        // 最低 1 の swarm にフォールバックする。
        case .subagentRunning: .swarm(active: 1)
        case .permissionWaiting: .alert
        case .error: .fault
        case .done: .complete
        }
    }
}

extension UnifiedSession {
    /// subagent 実行中は親セッション（や subagent 自身）の PreToolUse/PostToolUse で
    /// status が toolRunning/thinking に頻繁に切り替わるため、status ではなく
    /// `runningSubagentCount` を見て swarm を維持する。
    /// 割り込み系（permission 待ち・エラー・完了）は swarm より優先して表示する。
    var glyphState: Glyph.State {
        switch status {
        case .permissionWaiting:
            // Plan モード終了確認（ExitPlanMode）は通常の alert とは別の図柄で識別する。
            if pendingPermissions.first?.isPlanReview == true {
                return .planReview
            }
            return status.glyphState
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
