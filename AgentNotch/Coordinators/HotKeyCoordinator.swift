import Foundation
import KeyboardShortcuts

/// グローバルホットキー登録。
/// - ⌥⇧N (`.jumpToNotification`) → `.agentNotchHotKeyJumpNotification` を発火
/// - ⌥⇧J (`.jumpToTerminal`)     → `.agentNotchHotKeyJumpTerminal` を発火
/// - ⌥⇧⏎ (`.approvePermission`)  → `.agentNotchHotKeyApprove` を発火
/// - ⌥⇧⌫ (`.denyPermission`)     → `.agentNotchHotKeyDeny` を発火
///
/// 実際のハンドリングは `NotchEventRouter` 側の onReceive が行う。
@MainActor
enum HotKeyCoordinator {
    static func register() {
        KeyboardShortcuts.onKeyUp(for: .jumpToNotification) {
            NotificationCenter.default.post(name: .agentNotchHotKeyJumpNotification, object: nil)
        }
        KeyboardShortcuts.onKeyUp(for: .jumpToTerminal) {
            NotificationCenter.default.post(name: .agentNotchHotKeyJumpTerminal, object: nil)
        }
        KeyboardShortcuts.onKeyUp(for: .approvePermission) {
            NotificationCenter.default.post(name: .agentNotchHotKeyApprove, object: nil)
        }
        KeyboardShortcuts.onKeyUp(for: .denyPermission) {
            NotificationCenter.default.post(name: .agentNotchHotKeyDeny, object: nil)
        }
    }
}
