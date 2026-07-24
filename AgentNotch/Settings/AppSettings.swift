import AgentNotchCore
import Defaults
import SwiftUI

enum CardPromptSource: String, Defaults.Serializable, CaseIterable, Sendable {
    case firstUserMessage
    case lastUserMessage

    var label: String {
        switch self {
        case .firstUserMessage: "最初のプロンプト"
        case .lastUserMessage: "最新のプロンプト"
        }
    }
}

// MARK: - Defaults conformance for Core types

extension SessionSortOrder: Defaults.Serializable {}
extension SessionGrouping: Defaults.Serializable {}
extension SessionUserState: Defaults.Serializable {}

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

// MARK: - Sound

/// Represents a sound source: system sound, custom file, or none.
struct SoundChoice: Codable, Defaults.Serializable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case none
        case system    // /System/Library/Sounds/{name}.aiff
        case custom    // User-provided file path
    }

    var kind: Kind
    var name: String  // System sound name (e.g. "Glass") or custom file path

    static let none = SoundChoice(kind: .none, name: "")
    static func system(_ name: String) -> SoundChoice { SoundChoice(kind: .system, name: name) }
    static func custom(_ path: String) -> SoundChoice { SoundChoice(kind: .custom, name: path) }

    var displayName: String {
        switch kind {
        case .none: "なし"
        case .system: name
        case .custom: (name as NSString).lastPathComponent
        }
    }

    /// All available macOS system sounds.
    static let systemSounds: [String] = {
        let dir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }()
}

/// Which events can trigger sounds.
enum SoundEvent: String, CaseIterable, Sendable {
    case sessionCompleted
    case subagentCompleted
    case permissionWaiting
    case error

    var label: String {
        switch self {
        case .sessionCompleted: "タスク完了"
        case .subagentCompleted: "サブエージェント完了"
        case .permissionWaiting: "権限待ち"
        case .error: "エラー"
        }
    }

    var icon: String {
        switch self {
        case .sessionCompleted: "checkmark.circle"
        case .subagentCompleted: "person.2.circle"
        case .permissionWaiting: "exclamationmark.triangle"
        case .error: "xmark.circle"
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

    // Sound settings per event
    static let soundCompleted = Key<SoundChoice>("soundCompleted", default: .system("Glass"))
    // subagent 完了は並列実行（Workflow で 5〜16 並行）だと頻発するため、デフォルトは無音。
    // 鳴らしたい場合は設定から選択する。
    static let soundSubagentCompleted = Key<SoundChoice>("soundSubagentCompleted", default: .none)
    static let soundPermission = Key<SoundChoice>("soundPermission", default: .system("Funk"))
    static let soundError = Key<SoundChoice>("soundError", default: .system("Basso"))
    static let soundEnabled = Key<Bool>("soundEnabled", default: true)

    // Session list sort / grouping
    static let sessionSortOrder = Key<SessionSortOrder>("sessionSortOrder", default: .latestActivity)
    static let sessionGrouping = Key<SessionGrouping>("sessionGrouping", default: .none)
    /// 折りたたまれているグループキーの集合（keys は groupKey 文字列）。
    static let collapsedGroupIDs = Key<Set<String>>("collapsedGroupIDs", default: [])

    /// セッションに対する user state（pin/mute/markedDoneAt）。キーは session ID。
    /// SessionManager からの変更通知で同期される。session 削除時にエントリも削除。
    static let sessionUserStates = Key<[String: SessionUserState]>("sessionUserStates", default: [:])

    /// セッションカードの目的行に表示するメッセージ。
    static let cardPromptSource = Key<CardPromptSource>("cardPromptSource", default: .firstUserMessage)
}
