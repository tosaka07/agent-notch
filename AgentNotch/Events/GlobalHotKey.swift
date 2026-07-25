import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Jump to the latest notification's terminal (or open session detail, per settings).
    static let jumpToNotification = Self("jumpToNotification", default: .init(.n, modifiers: [.option, .shift]))

    /// Jump to current session's terminal (active in session detail view).
    static let jumpToTerminal = Self("jumpToTerminal", default: .init(.j, modifiers: [.option, .shift]))

    /// 表示中の権限リクエストを承認する。
    ///
    /// `NotchPanel` は `.nonactivatingPanel` で、バナーが出た時点ではキーウィンドウに
    /// なれない（クリックするまで ⏎ が効かない）。フォーカスを奪うのは危険なので、
    /// **アプリが非アクティブでも効くグローバルホットキー**を用意する。
    ///
    /// 既定は既存の ⌥⇧N / ⌥⇧J と同系統にする。⌘⏎ のような一般的な組み合わせを
    /// 既定にすると、他アプリ（送信・改行）から奪ってしまうため。
    static let approvePermission = Self("approvePermission", default: .init(.return, modifiers: [.option, .shift]))

    /// 表示中の権限リクエストを拒否する。
    static let denyPermission = Self("denyPermission", default: .init(.delete, modifiers: [.option, .shift]))
}
