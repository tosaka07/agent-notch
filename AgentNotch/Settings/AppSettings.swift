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

/// ExpandedPageView トップバー左翼の常時表示ゲージの見せ方。設定から選ぶ。
///
/// ゲージ本体のクリックは「使用量の詳細ページを開く」に割り当てているため、
/// 表示形式の切り替えはタップではなく設定に置いている。
enum UsageGaugeStyle: String, Defaults.Serializable, CaseIterable, Sendable {
    /// リングのみ（ドットの円環で使用率を示す）。
    case ring
    /// 数字のみ（2 桁のピクセル数字）。
    case number

    var label: String {
        switch self {
        case .ring: "リング"
        case .number: "数字"
        }
    }
}

/// 展開パネルの背景の作り方。
///
/// notch は「上端が物理的な黒に接している」という制約があるので、上は必ず不透明な黒。
/// 下端をどう終わらせるかだけが選択肢になる。
enum PanelSurfaceStyle: String, Defaults.Serializable, CaseIterable, Sendable {
    /// 一様な暗幕（従来）。パネル全体が同じ濃さの半透明。
    case solid
    /// 上端は不透明な黒のまま、**下端に向かって material へ移行**する。
    /// 下端の縁にわずかな光沢を足して、板ではなくガラスの縁に見せる（近似）。
    case gradient
    /// `gradient` と同じ構成だが、面を **macOS 26 の Liquid Glass**（`glassEffect`）で作る。
    /// material の近似ではなく本物のガラスなので、下端は完全に抜いて素のガラスを見せる。
    case liquidGlass

    var label: String {
        switch self {
        case .solid: "フラット"
        case .gradient: "すりガラス"
        case .liquidGlass: "リキッドグラス"
        }
    }
}

/// `UsageGaugeMetric`（どの枠をゲージに出すか）を設定として永続化する。
///
/// enum 自体は選択ロジックと一緒に `AgentNotchCore` に置いてある（Core は Defaults に
/// 依存しないため、`Defaults.Serializable` 準拠だけを GUI 側で足す）。
extension UsageGaugeMetric: Defaults.Serializable {}

extension UsageGaugeMetric {
    var label: String {
        switch self {
        case .auto: "自動（最も逼迫している枠）"
        case .session: "セッション（5 時間枠）"
        case .weekly: "ウィークリー（全モデル）"
        case .weeklyModel: "ウィークリー（モデル別の最大）"
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

    /// ExpandedPageView トップバー左翼の常時表示ゲージ（リング / 数字）の表示形式。
    static let usageGaugeStyle = Key<UsageGaugeStyle>("usageGaugeStyle", default: .ring)

    /// 常時表示ゲージにどの枠（セッション / ウィークリー / …）を出すか。
    static let usageGaugeMetric = Key<UsageGaugeMetric>("usageGaugeMetric", default: .auto)

    /// 展開パネルの背景（フラット / 下端がガラスに移行）。
    /// 既定は従来の見え方（`.solid`）。
    static let panelSurfaceStyle = Key<PanelSurfaceStyle>("panelSurfaceStyle", default: .solid)

    /// ExpandedPageView 下部の USAGE セクションが折りたたまれているか。
    /// 旧横長バー（#39 で SessionDetailView のゲージに統合され削除）の名残。
    /// 参照箇所は無いが、既存ユーザーの Defaults を無用に破棄しないため定義のみ残す。
    static let usageSectionCollapsed = Key<Bool>("usageSectionCollapsed", default: false)

    /// 使用量（USAGE）表示を行うか。
    ///
    /// OFF にすると Claude の資格情報にも undocumented API にも一切触らなくなる。
    /// issue #35 の認証ダイアログは `ClaudeCredentialsStore` 側で根本対処済みのため
    /// デフォルトは ON（PR #34 で出荷した表示を黙って無効化しないため）。
    /// ダイアログが出る環境ではユーザーがここを OFF にすれば完全に止められる。
    static let usageEnabled = Key<Bool>("usageEnabled", default: true)
}
