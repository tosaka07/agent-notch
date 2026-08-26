import KeyboardShortcuts

enum GlobalHotKeyAction: Sendable {
    case focusPanel
    case jumpToTerminal
    case approvePermission
    case denyPermission
}

extension KeyboardShortcuts.Name {
    /// Enter or leave Agent Notch's explicit keyboard-interaction mode.
    static let jumpToNotification = Self(
        "jumpToNotification", default: .init(.n, modifiers: [.option, .shift]))

    /// Jump to current session's terminal (active in session detail view).
    static let jumpToTerminal = Self("jumpToTerminal", default: .init(.j, modifiers: [.option, .shift]))

    /// Approves the visible permission request.
    ///
    /// `NotchPanel` is a `.nonactivatingPanel`, so it cannot become the key window when
    /// the banner appears — ⏎ does nothing until the panel is clicked. Stealing focus
    /// would be worse, so this is a global hot key that works even while the app is
    /// inactive.
    ///
    /// The default stays in the same family as ⌥⇧N / ⌥⇧J. A common combination such as
    /// ⌘⏎ would be stolen from other apps, where it means send or newline.
    static let approvePermission = Self(
        "approvePermission", default: .init(.return, modifiers: [.option, .shift]))

    /// Denies the visible permission request.
    static let denyPermission = Self("denyPermission", default: .init(.delete, modifiers: [.option, .shift]))
}
