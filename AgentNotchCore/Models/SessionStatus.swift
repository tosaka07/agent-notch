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

    /// Whether this status represents active work (notch should show wings)
    public var isActive: Bool {
        switch self {
        case .thinking, .toolRunning, .subagentRunning, .permissionWaiting, .compacting, .done, .error:
            return true
        case .starting, .idle, .completed:
            return false
        }
    }
}
