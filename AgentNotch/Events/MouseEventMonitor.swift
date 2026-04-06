import AppKit

@MainActor
final class MouseEventMonitor {
    private var globalMonitor: Any?

    func startMonitoring(
        mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated {
                handler(event)
            }
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        // Monitors must be removed on main actor; caller should call stopMonitoring() before deinit.
    }
}
