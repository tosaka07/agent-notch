import SwiftUI

public enum SessionStatus: String, Codable, Sendable {
    case starting, idle, thinking, toolRunning, permissionWaiting, compacting, error, completed

    public var color: Color {
        switch self {
        case .starting, .idle: .gray
        case .thinking: .orange
        case .toolRunning: .green
        case .permissionWaiting, .error: .red
        case .compacting: .purple
        case .completed: .blue
        }
    }

    public var label: String {
        switch self {
        case .starting: "Starting"
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .toolRunning: "Running tool"
        case .permissionWaiting: "Waiting for approval"
        case .compacting: "Compacting"
        case .error: "Error"
        case .completed: "Completed"
        }
    }
}
