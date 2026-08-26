import AgentNotchCore
import AppKit
import SwiftUI

/// The settings window.
///
/// SwiftUI's `NavigationSplitView` owns the sidebar/content composition so the
/// title bar, traffic lights, sidebar material, selection, and section headings
/// follow the standard macOS window behavior.
///
/// # Height
/// The content height stays fixed. Every settings pane is a SwiftUI `Form`, so
/// content that exceeds the viewport scrolls without resizing the window.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let selection = SettingsSelection()

    /// Whether settings is on screen. `OnboardingWindowController` asks before dropping the app
    /// back to accessory, since a replayed tour is launched from here.
    var isVisible: Bool { window?.isVisible == true }

    func show(sessionManager: SessionManager, tab: SettingsTab? = nil) {
        if let tab {
            selection.tab = tab
        }

        if let window {
            window.makeKeyAndOrderFront(nil)
            activateForSettings()
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsSplitView(
                selection: selection,
                sessionManager: sessionManager
            )
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindowSizing.preferredWindowContentWidth,
                height: SettingsWindowSizing.fixedContentHeight
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(
            width: SettingsWindowSizing.minimumWindowContentWidth,
            height: SettingsWindowSizing.fixedContentHeight
        )
        window.contentMaxSize = NSSize(
            width: SettingsWindowSizing.maximumWindowContentWidth,
            height: SettingsWindowSizing.fixedContentHeight
        )
        window.title = "Agent Notch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        window.layoutIfNeeded()
        hostingController.view.layoutSubtreeIfNeeded()
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateForSettings()
    }

    // MARK: - Activation

    /// Temporarily become a regular app so the window can receive key input.
    private func activateForSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Return to accessory (LSUIElement) once settings closes.
    func windowWillClose(_ notification: Notification) {
        // Wait for the window to finish closing before switching back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
enum SettingsWindowSizing {
    static let sidebarWidth: CGFloat = 210
    static let minimumSidebarWidth: CGFloat = 180
    static let maximumSidebarWidth: CGFloat = 280
    static let splitViewDividerWidth: CGFloat = 1

    static let preferredWindowContentWidth =
        sidebarWidth + SettingsView.contentWidth + splitViewDividerWidth
    static let minimumWindowContentWidth =
        minimumSidebarWidth + SettingsView.minimumContentWidth
        + splitViewDividerWidth
    static let maximumWindowContentWidth: CGFloat = 1_600
    static let fixedContentHeight: CGFloat = 600
}
