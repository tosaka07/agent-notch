import Defaults
import SwiftUI

enum TextSizePreference: String, Defaults.Serializable, CaseIterable, Sendable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 1.0
        case .medium: 1.1
        case .large: 1.2
        }
    }

    /// Scale a base font size, rounding to nearest 0.5
    func scaled(_ base: CGFloat) -> CGFloat {
        (base * scale * 2).rounded() / 2
    }
}

enum SessionTimeoutPreference: Int, Defaults.Serializable, CaseIterable, Sendable {
    case oneHour = 3600
    case sixHours = 21600
    case oneDay = 86400
    case threeDays = 259200
    case never = 0

    var label: String {
        switch self {
        case .oneHour: "1時間"
        case .sixHours: "6時間"
        case .oneDay: "1日"
        case .threeDays: "3日"
        case .never: "なし"
        }
    }
}

enum NotificationTapAction: String, Defaults.Serializable, CaseIterable, Sendable {
    case jumpToTerminal
    case openSessionDetail

    var label: String {
        switch self {
        case .jumpToTerminal: "ターミナルへ移動"
        case .openSessionDetail: "セッション詳細を開く"
        }
    }
}

enum DisplayModePreference: String, Defaults.Serializable, CaseIterable, Sendable {
    case followFocus
    case allDisplays
    case builtinOnly
    case specificDisplay

    var label: String {
        switch self {
        case .followFocus: "フォーカス追従"
        case .allDisplays: "全ディスプレイ"
        case .builtinOnly: "内蔵のみ"
        case .specificDisplay: "指定ディスプレイ"
        }
    }
}

extension Defaults.Keys {
    static let textSize = Key<TextSizePreference>("textSize", default: .small)
    static let sessionTimeout = Key<SessionTimeoutPreference>("sessionTimeout", default: .oneDay)
    static let notificationTapAction = Key<NotificationTapAction>("notificationTapAction", default: .jumpToTerminal)
    static let displayMode = Key<DisplayModePreference>("displayMode", default: .followFocus)
    /// UUID of the specific display chosen when displayMode == .specificDisplay
    static let specificDisplayUUID = Key<String>("specificDisplayUUID", default: "")
}
