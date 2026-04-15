import Foundation

enum NotchMode: Equatable, Sendable, CustomStringConvertible {
    case compact
    case notification
    case expanded
    case sessionDetail(sessionId: String)

    var isSessionDetail: Bool {
        if case .sessionDetail = self { return true }
        return false
    }

    var isFullPanel: Bool {
        switch self {
        case .expanded, .sessionDetail: true
        default: false
        }
    }

    var description: String {
        switch self {
        case .compact: "compact"
        case .notification: "notification"
        case .expanded: "expanded"
        case .sessionDetail(let id): "sessionDetail(\(id.prefix(8)))"
        }
    }
}
