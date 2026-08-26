import Foundation

enum NotchMode: Equatable, Sendable, CustomStringConvertible {
    case compact
    case notification
    case expanded
    case sessionDetail(sessionId: String)
    /// The usage detail page. Opened by clicking the gauge on the left of the
    /// session list's top bar.
    case usage

    var isFullPanel: Bool {
        switch self {
        case .expanded, .sessionDetail, .usage: true
        default: false
        }
    }

    var description: String {
        switch self {
        case .compact: "compact"
        case .notification: "notification"
        case .expanded: "expanded"
        case .sessionDetail(let id): "sessionDetail(\(id.prefix(8)))"
        case .usage: "usage"
        }
    }
}
