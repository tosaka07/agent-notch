import Foundation

public struct ChatEntry: Identifiable, Sendable {
    public let id: String
    public let role: Role
    public let textContent: String
    public let toolUses: [ToolUseEntry]
    public let timestamp: Date?

    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public struct ToolUseEntry: Sendable {
        public let name: String
        public let inputSummary: String

        public init(name: String, inputSummary: String) {
            self.name = name
            self.inputSummary = inputSummary
        }
    }

    public init(
        id: String = UUID().uuidString, role: Role, textContent: String, toolUses: [ToolUseEntry] = [],
        timestamp: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.textContent = textContent
        self.toolUses = toolUses
        self.timestamp = timestamp
    }
}
