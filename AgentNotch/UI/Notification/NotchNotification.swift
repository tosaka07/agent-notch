import Foundation

@MainActor @Observable
final class NotchNotificationManager {
    struct Item: Identifiable {
        let id: String
        let projectName: String
        let gitBranch: String?
        let message: String
        let createdAt: Date
    }

    private(set) var items: [Item] = []
    private var dismissTasks: [String: Task<Void, Never>] = [:]

    /// Maximum stacked notifications
    private let maxVisible = 4
    /// Minimum display time before auto-dismiss (used when no marquee)
    private let minDisplaySeconds: TimeInterval = 8

    var isEmpty: Bool { items.isEmpty }
    var hasNotification: Bool { !items.isEmpty }

    func enqueue(_ item: Item) {
        // Prevent duplicates
        guard !items.contains(where: { $0.id == item.id }) else { return }
        if items.count >= maxVisible {
            // Remove oldest to make room
            let oldest = items[0]
            dismiss(id: oldest.id)
        }
        items.append(item)
        // Schedule a fallback dismiss (in case marquee callback never fires)
        scheduleFallbackDismiss(id: item.id)
    }

    /// Called by MarqueeText when its first cycle completes.
    /// Starts a short linger timer then removes the item.
    func marqueeCompleted(id: String) {
        // Cancel any existing fallback timer
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            dismiss(id: id)
        }
    }

    /// Called when item has no marquee — start dismiss timer from ready.
    func scheduleStaticDismiss(id: String) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(minDisplaySeconds)  )
            guard !Task.isCancelled else { return }
            dismiss(id: id)
        }
    }

    func dismiss(id: String) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
        items.removeAll { $0.id == id }
    }

    func dismissAll() {
        for task in dismissTasks.values { task.cancel() }
        dismissTasks.removeAll()
        items.removeAll()
    }

    /// Safety net: auto-dismiss after a generous timeout regardless of marquee state.
    private func scheduleFallbackDismiss(id: String) {
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            dismiss(id: id)
        }
    }
}
