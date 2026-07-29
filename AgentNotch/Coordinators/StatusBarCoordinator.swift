import AgentNotchCore
import AppKit
import Defaults

/// Manages the menu bar icon (`NSStatusItem`) and its menu.
/// Provides About / Settings / Quit.
@MainActor
final class StatusBarCoordinator: NSObject, NSMenuDelegate {
    private let sessionManager: SessionManager
    private var statusItem: NSStatusItem?
    private weak var settingsMenuItem: NSMenuItem?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        // Use the product symbol rather than a borrowed SF Symbol.
        // It is a template image, so macOS tints it for light/dark and selection.
        button.image = ProductMark.menuBarImage()

        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: L("About Agent Notch"), action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: L("Settings…"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.isEnabled = Defaults[.hasCompletedOnboarding]
        settingsMenuItem = settingsItem
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // The menu items target this coordinator.
        for menuItem in menu.items
        where menuItem.action == #selector(showAbout) || menuItem.action == #selector(showSettings) {
            menuItem.target = self
        }
        menu.delegate = self
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        settingsMenuItem?.isEnabled = Defaults[.hasCompletedOnboarding]
    }

    @objc private func showAbout() {
        guard Defaults[.hasCompletedOnboarding] else {
            NSApp.orderFrontStandardAboutPanel()
            return
        }
        SettingsWindowController.shared.show(sessionManager: sessionManager, tab: .about)
    }

    @objc private func showSettings() {
        guard Defaults[.hasCompletedOnboarding] else { return }
        SettingsWindowController.shared.show(sessionManager: sessionManager)
    }
}
