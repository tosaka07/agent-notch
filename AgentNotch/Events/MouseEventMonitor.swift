import AppKit

@MainActor
final class MouseEventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func startMonitoring(
        mask: NSEvent.EventTypeMask,
        globalHandler: @escaping @MainActor (NSEvent) -> Void,
        localHandler: (@MainActor (NSEvent) -> Bool)? = nil
    ) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated {
                globalHandler(event)
            }
        }

        if let localHandler {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
                let consumed = MainActor.assumeIsolated {
                    localHandler(event)
                }
                return consumed ? nil : event
            }
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
