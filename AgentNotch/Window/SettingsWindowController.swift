import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        window.level = .floating  // Above other windows so Recorder can capture keys
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}
