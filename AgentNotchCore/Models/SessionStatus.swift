import SwiftUI

public enum SessionStatus: String, Codable, Sendable {
    case starting
    case idle
    case thinking          // Claude is reasoning (after UserPromptSubmit)
    case toolRunning       // Executing a tool (PreToolUse → PostToolUse)
    case subagentRunning   // Subagent is active (SubagentStart → SubagentStop)
    case permissionWaiting // Waiting for user approval (PermissionRequest)
    case compacting        // Context compaction (PreCompact → PostCompact)
    case done              // Turn complete, waiting for input (Stop) — temporary, fades to idle
    case error             // API error / tool failure (StopFailure)
    case completed         // Session ended (SessionEnd) — removed from list

    public var color: Color {
        switch self {
        case .starting, .idle: .gray
        case .thinking: .blue
        case .toolRunning: .blue
        case .subagentRunning: .cyan
        case .permissionWaiting: .orange
        case .compacting: .purple
        case .done: .green
        case .error: .red
        case .completed: .gray
        }
    }

    public var label: String {
        switch self {
        case .starting: "Starting"
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .toolRunning: "Running"
        case .subagentRunning: "Subagent"
        case .permissionWaiting: "Approval"
        case .compacting: "Compacting"
        case .done: "Done"
        case .error: "Error"
        case .completed: "Ended"
        }
    }

    /// Whether this status means the session is actively doing work (thinking, running tools, etc.)
    public var isRunning: Bool {
        switch self {
        case .thinking, .toolRunning, .subagentRunning, .compacting:
            return true
        default:
            return false
        }
    }

    /// Whether this status represents active work (notch should show wings)
    public var isActive: Bool {
        switch self {
        case .thinking, .toolRunning, .subagentRunning, .permissionWaiting, .compacting, .done, .error:
            return true
        case .starting, .idle, .completed:
            return false
        }
    }

    /// 要介入度のランク（0 が最も緊急、値が大きいほど緊急度が低い）。
    /// CompactPageView の `mostUrgentStatus()` と整合する優先度。
    public var urgencyRank: Int {
        switch self {
        case .permissionWaiting: return 0
        case .error: return 1
        case .toolRunning: return 2
        case .thinking: return 3
        case .subagentRunning: return 4
        case .compacting: return 5
        case .done: return 6
        case .idle: return 7
        case .starting: return 8
        case .completed: return 9
        }
    }
}
