import Foundation

public struct ToolInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let input: [String: String]
    public let startedAt: Date
    public var completedAt: Date?
    public var status: ToolStatus
    public var durationMs: Int?

    public enum ToolStatus: String, Sendable {
        case running, succeeded, failed, denied
    }

    public init(id: String, name: String, summary: String, input: [String: String], startedAt: Date, completedAt: Date? = nil, status: ToolStatus, durationMs: Int? = nil) {
        self.id = id; self.name = name; self.summary = summary; self.input = input
        self.startedAt = startedAt; self.completedAt = completedAt; self.status = status; self.durationMs = durationMs
    }
}
