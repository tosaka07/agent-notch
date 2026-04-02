import SwiftUI

public enum AgentType: String, Codable, Sendable, CaseIterable {
    case claudeCode, codex, geminiCLI, custom

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .custom: "Custom"
        }
    }

    public var color: Color {
        switch self {
        case .claudeCode: .orange
        case .codex: .blue
        case .geminiCLI: .green
        case .custom: .purple
        }
    }
}
