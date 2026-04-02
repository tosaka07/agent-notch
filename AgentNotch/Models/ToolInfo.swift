import Foundation

struct ToolInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let input: [String: String]
    let startedAt: Date
    var completedAt: Date?
    var status: ToolStatus
    var durationMs: Int?

    enum ToolStatus: String, Sendable {
        case running, succeeded, failed, denied
    }
}
