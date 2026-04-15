import AgentNotchCore
import AppKit
import SwiftUI

/// 通知キーボードフォーカス（⌥⇧N で通知一覧に focus し j/k/Enter/Esc で操作）の state と
/// NSEvent ローカルモニターのライフサイクルを保持する。
///
/// - `focus(manager:)` / `unfocus(manager:)` / `handleKey(_:manager:)` を View から呼ぶ。
/// - `NotchNotificationManager` の items を直接操作する（pauseAutoDismiss, dismiss）ため、
///   操作時に manager を渡す設計（Controller 側は manager を保持しない）。
@MainActor
@Observable
final class NotificationFocusController {
    var isFocused: Bool = false
    var focusIndex: Int = 0

    @ObservationIgnored
    private var keyMonitor: Any?

    func focus(manager: NotchNotificationManager) {
        isFocused = true
        focusIndex = manager.items.count - 1  // latest
        manager.pauseAutoDismiss = true
        NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: true)
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak manager] event in
                guard let self, let manager else { return event }
                return self.handleKey(event, manager: manager)
            }
        }
        Log.notification.info("Keyboard focus ON, index=\(focusIndex)")
    }

    func unfocus(manager: NotchNotificationManager) {
        isFocused = false
        manager.pauseAutoDismiss = false
        NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: false)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        Log.notification.info("Keyboard focus OFF")
    }

    /// 通知数が減ったときに index を最大値にクランプ
    func clampIndex(maxCount: Int) {
        guard maxCount > 0 else { return }
        focusIndex = min(focusIndex, maxCount - 1)
    }

    private func handleKey(_ event: NSEvent, manager: NotchNotificationManager) -> NSEvent? {
        guard isFocused, !manager.items.isEmpty else { return event }
        let items = manager.items
        let keyCode = event.keyCode
        let ctrl = event.modifierFlags.contains(.control)

        switch keyCode {
        case 0x28 where !ctrl, 0x7E:  // k, ↑
            focusIndex = max(0, focusIndex - 1)
            return nil
        case 0x23 where ctrl:  // Ctrl+P
            focusIndex = max(0, focusIndex - 1)
            return nil
        case 0x26 where !ctrl, 0x7D:  // j, ↓
            focusIndex = min(items.count - 1, focusIndex + 1)
            return nil
        case 0x2D where ctrl:  // Ctrl+N
            focusIndex = min(items.count - 1, focusIndex + 1)
            return nil
        case 0x24:  // Return
            let idx = min(focusIndex, items.count - 1)
            let item = items[idx]
            item.onTap?()
            // Dismiss only the acted-upon notification
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                manager.dismiss(id: item.id)
            }
            // If more remain, keep focus and clamp index
            if manager.items.isEmpty {
                unfocus(manager: manager)
            } else {
                focusIndex = min(focusIndex, manager.items.count - 1)
            }
            return nil
        case 0x35:  // Escape
            unfocus(manager: manager)
            return nil
        default:
            return event
        }
    }
}
