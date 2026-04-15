import Foundation

/// セッションに対してユーザーが付与した状態。
/// agent からのイベントとは独立して管理し、`session.status` を上書きしない。
///
/// - `pinned`: セッション一覧で常に先頭に並べる。
/// - `muted`: サウンド再生・auto-expand・NotchNotification を抑止する。
/// - `markedDoneAt`: ユーザーが「このターンはもう見ない」とマークした時刻。
///                   `session.lastActivityAt <= markedDoneAt` の間だけ done 扱い。
///                   新しい activity が来ると自動的に解除される。
public struct SessionUserState: Codable, Equatable, Sendable {
    public var pinned: Bool
    public var muted: Bool
    public var markedDoneAt: Date?

    public init(
        pinned: Bool = false,
        muted: Bool = false,
        markedDoneAt: Date? = nil
    ) {
        self.pinned = pinned
        self.muted = muted
        self.markedDoneAt = markedDoneAt
    }

    public static let empty = SessionUserState()

    /// 全てデフォルト値の状態かどうか。永続化から除去してよいかの判定に使う。
    public var isDefault: Bool {
        !pinned && !muted && markedDoneAt == nil
    }
}

/// `SessionManager.groupedSessions(...)` の戻り値。
public struct SessionGroup: Identifiable, Sendable {
    /// `Identifiable` 用のキー。グループ化軸ごとに生成される一意キー。
    public let key: String
    public var id: String { key }
    /// UI に表示するグループタイトル（例: "Claude Code", "Waiting"）。
    /// `grouping == .none` の場合は空文字列。
    public let title: String
    public let sessions: [UnifiedSession]

    public init(key: String, title: String, sessions: [UnifiedSession]) {
        self.key = key
        self.title = title
        self.sessions = sessions
    }
}
