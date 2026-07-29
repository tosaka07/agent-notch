import AgentNotchCore
import SwiftUI

/// Holds the state for keyboard focus on notifications. ⌥⇧N engages the panel,
/// then the shared keyboard interaction controller drives the list.
///
/// - Views call `focus(manager:)` / `unfocus(manager:)` / `move` / `activate`.
/// - The manager is passed in per call rather than retained, because the
///   controller mutates `NotchNotificationManager`'s items directly
///   (pauseAutoDismiss, dismiss).
@MainActor
@Observable
final class NotificationFocusController {
    var isFocused: Bool = false
    var focusIndex: Int = 0

    func focus(manager: NotchNotificationManager) {
        isFocused = true
        focusIndex = manager.items.count - 1  // latest
        manager.pauseAutoDismiss = true
        Log.notification.info("Keyboard focus ON, index=\(focusIndex)")
    }

    func unfocus(manager: NotchNotificationManager) {
        isFocused = false
        manager.pauseAutoDismiss = false
        Log.notification.info("Keyboard focus OFF")
    }

    /// Clamps the index to the last item when the notification count shrinks.
    func clampIndex(maxCount: Int) {
        guard maxCount > 0 else { return }
        focusIndex = min(focusIndex, maxCount - 1)
    }

    func move(by delta: Int, manager: NotchNotificationManager) {
        guard isFocused, !manager.items.isEmpty else { return }
        focusIndex = min(max(0, focusIndex + delta), manager.items.count - 1)
    }

    func activate(manager: NotchNotificationManager) {
        guard isFocused, !manager.items.isEmpty else { return }
        let items = manager.items
        let idx = min(focusIndex, items.count - 1)
        let item = items[idx]
        item.onTap?()
        // Dismiss only the acted-upon notification.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            manager.dismiss(id: item.id)
        }
        if manager.items.isEmpty {
            unfocus(manager: manager)
        } else {
            focusIndex = min(focusIndex, manager.items.count - 1)
        }
    }
}
