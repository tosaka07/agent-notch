import AgentNotchCore
import SwiftUI

@MainActor @Observable
final class NotchNotificationManager {
    struct Item: Identifiable {
        let id: String
        let content: AnyView
        let autoDismissAfter: TimeInterval?  // nil = fallback only (30s)
        let createdAt: Date
        var onTap: (() -> Void)?
    }

    private(set) var items: [Item] = []
    private var dismissTasks: [String: Task<Void, Never>] = [:]

    private let maxVisible = 4
    private let fallbackTimeout: TimeInterval = 12

    var isEmpty: Bool { items.isEmpty }
    var hasNotification: Bool { !items.isEmpty }

    func enqueue(_ item: Item) {
        guard !items.contains(where: { $0.id == item.id }) else {
            Log.notification.debug("Enqueue skipped, duplicate id=\(item.id)")
            return
        }
        if items.count >= maxVisible {
            Log.notification.debug("Queue full, evicting id=\(self.items[0].id)")
            dismiss(id: items[0].id)
        }
        Log.notification.info("Enqueue notification id=\(item.id)")
        items.append(item)

        if let delay = item.autoDismissAfter {
            scheduleDismiss(id: item.id, after: delay)
        } else {
            scheduleDismiss(id: item.id, after: fallbackTimeout)
        }
    }

    /// Called from content view (e.g. marquee complete) to dismiss after a short linger.
    func requestDismiss(id: String, afterLinger: TimeInterval = 2) {
        Log.notification.debug("requestDismiss id=\(id) linger=\(afterLinger)s")
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(afterLinger))
            guard !Task.isCancelled else { return }
            dismiss(id: id)
        }
    }

    func dismiss(id: String) {
        Log.notification.info("Dismiss notification id=\(id)")
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
        items.removeAll { $0.id == id }
    }

    func dismissAll() {
        for task in dismissTasks.values { task.cancel() }
        dismissTasks.removeAll()
        items.removeAll()
    }

    private func scheduleDismiss(id: String, after delay: TimeInterval) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            dismiss(id: id)
        }
    }
}
