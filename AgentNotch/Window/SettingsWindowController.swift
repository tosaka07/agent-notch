import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            activateApp()
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
        // Above notch panel (mainMenu+3) so key events go to settings, not through to other apps
        window.level = .init(NSWindow.Level.mainMenu.rawValue + 10)
        window.makeKeyAndOrderFront(nil)
        activateApp()
        self.window = window
    }

    private func activateApp() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
