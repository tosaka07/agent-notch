import AgentNotchCore
import AppKit

/// メニューバーアイコン（NSStatusItem）と付随メニューを管理する。
/// About / Clear All Sessions / Quit を提供する。
@MainActor
final class StatusBarCoordinator: NSObject {
    private let sessionManager: SessionManager
    private var statusItem: NSStatusItem?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agent Notch")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Agent Notch", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear All Sessions", action: #selector(clearSessions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // menu item のターゲットは Coordinator 自身
        for menuItem in menu.items where menuItem.action == #selector(showAbout) || menuItem.action == #selector(clearSessions) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel() }

    @objc private func clearSessions() {
        sessionManager.removeAllSessions()
        sessionManager.notifyChange()
    }
}
