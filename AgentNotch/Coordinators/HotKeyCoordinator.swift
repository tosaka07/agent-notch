import Foundation
import KeyboardShortcuts

/// Global hot key registration.
/// - ⌥⇧N (`.jumpToNotification`) → enters/leaves keyboard interaction
/// - ⌥⇧J (`.jumpToTerminal`)     → jumps to the visible session's terminal
/// - ⌥⇧⏎ (`.approvePermission`)  → approves the visible permission
/// - ⌥⇧⌫ (`.denyPermission`)     → denies the visible permission
///
/// The actual handling is routed to exactly one display by `DisplayCoordinator`.
@MainActor
final class HotKeyCoordinator {
    private let handler: @MainActor (GlobalHotKeyAction) -> Void

    init(handler: @escaping @MainActor (GlobalHotKeyAction) -> Void) {
        self.handler = handler
    }

    func register() {
        KeyboardShortcuts.onKeyUp(for: .jumpToNotification) {
            self.handler(.focusPanel)
        }
        KeyboardShortcuts.onKeyUp(for: .jumpToTerminal) {
            self.handler(.jumpToTerminal)
        }
        KeyboardShortcuts.onKeyUp(for: .approvePermission) {
            self.handler(.approvePermission)
        }
        KeyboardShortcuts.onKeyUp(for: .denyPermission) {
            self.handler(.denyPermission)
        }
    }
}
