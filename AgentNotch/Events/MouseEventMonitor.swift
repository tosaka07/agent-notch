import AppKit

@MainActor
final class MouseEventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func startMonitoring(
        globalMask: NSEvent.EventTypeMask,
        localMask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask) { event in
            MainActor.assumeIsolated {
                handler(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { event in
            MainActor.assumeIsolated {
                handler(event)
            }
            return event
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        // Monitors must be removed on main actor; caller should call stopMonitoring() before deinit.
    }
}
