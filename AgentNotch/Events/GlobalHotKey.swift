import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Jump to the latest notification's terminal (or open session detail, per settings).
    static let jumpToNotification = Self("jumpToNotification", default: .init(.n, modifiers: [.option, .shift]))

    /// Jump to current session's terminal (active in session detail view).
    static let jumpToTerminal = Self("jumpToTerminal", default: .init(.j, modifiers: [.option, .shift]))
}
