import Foundation

enum NotchMode: Equatable, Sendable, CustomStringConvertible {
    case compact
    case notification
    case expanded
    case sessionDetail(sessionId: String)
    /// 使用量（USAGE）の詳細ページ。一覧トップバー左翼のゲージをクリックして開く。
    case usage

    var isSessionDetail: Bool {
        if case .sessionDetail = self { return true }
        return false
    }

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
