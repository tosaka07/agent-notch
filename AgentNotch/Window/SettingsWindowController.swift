import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            activateForSettings()
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Notch Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        activateForSettings()
        self.window = window
    }

    /// Temporarily become a regular app so we can receive key events.
    private func activateForSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Go back to accessory (LSUIElement) when settings close.
    func windowWillClose(_ notification: Notification) {
        // Small delay to let the window fully close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
