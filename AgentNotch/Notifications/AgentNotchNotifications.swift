import Foundation

/// Agent Notch 内部で使う NotificationCenter 通知名の集約。
///
/// - UI への自動展開や通知表示トリガ、ホットキー到達通知などアプリ内の副作用 dispatch に使う。
/// - 外部プロセス（hook / socket）との通信はここを経由せず、SocketCoordinator が直接 SessionManager を更新する。
extension Notification.Name {
    /// セッションが新しい要求・入力を持ったので notch を展開してほしい（object: sessionId）
    static let agentNotchAutoExpand = Notification.Name("agentNotchAutoExpand")
    /// セッション完了通知（object: sessionId, userInfo: projectName/title/branch/message/pid/tty/...）
    static let agentNotchSessionCompleted = Notification.Name("agentNotchSessionCompleted")
    /// セッションが sweep で削除された（object: sessionId, userInfo: projectName/message/...）
    static let agentNotchSessionSwept = Notification.Name("agentNotchSessionSwept")
    /// パネルを閉じる
    static let agentNotchClosePanel = Notification.Name("agentNotchClosePanel")
    /// ユーザーがセッションに戻った（object: sessionId） — 関連通知と glow を解除する
    static let agentNotchSessionResumed = Notification.Name("agentNotchSessionResumed")
    /// ⌥⇧N — 通知一覧にキーボードフォーカス
    static let agentNotchHotKeyJumpNotification = Notification.Name("agentNotchHotKeyJumpNotification")
    /// ⌥⇧J — 現在表示中のセッションのターミナルへジャンプ
    static let agentNotchHotKeyJumpTerminal = Notification.Name("agentNotchHotKeyJumpTerminal")
    /// ⌥⇧⏎: 表示中の権限リクエストを承認する。
    static let agentNotchHotKeyApprove = Notification.Name("agentNotchHotKeyApprove")
    /// ⌥⇧⌫: 表示中の権限リクエストを拒否する。
    static let agentNotchHotKeyDeny = Notification.Name("agentNotchHotKeyDeny")
    /// NotchPanel のキーフォーカスを有効/無効にする（object: Bool）
    static let agentNotchSetKeyFocus = Notification.Name("agentNotchSetKeyFocus")
}
