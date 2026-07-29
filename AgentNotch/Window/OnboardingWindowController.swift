import AppKit
import SwiftUI

/// Owns the first-run window for this otherwise menu-bar-only app.
///
/// The same window is reused when the tour is replayed from Settings, so it is rebuilt with a
/// fresh `OnboardingView` on every `show` — the view keeps the current page in `@State`, and a
/// window left over from an earlier run would reopen on whatever page it ended on.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<OnboardingView>?
    private var onCompletion: (() -> Void)?

    /// - Parameter initialStep: `.blocked` when a previous launch reached the consent page and
    ///   left without installing, so the tour is not replayed.
    func show(initialStep: OnboardingStep = .welcome, onCompletion: @escaping () -> Void) {
        self.onCompletion = onCompletion

        if let window, let hostingView {
            hostingView.rootView = makeContent(initialStep: initialStep)
            window.makeKeyAndOrderFront(nil)
            activate()
            return
        }

        let hostingView = NSHostingView(rootView: makeContent(initialStep: initialStep))
        // The page fills whatever the window gives it, so the hosting view must not push its own
        // fitting size back into the window's frame.
        hostingView.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.windowSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = L("Welcome to Agent Notch")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // The page paints `.windowBackground` itself; the window color matches so the titlebar
        // strip and the rounded corners never show a different shade than the content.
        //
        // The appearance is pinned to dark for the same reason `OnboardingView` pins its color
        // scheme: the pages show the notch itself — black silhouette, lit dot glyphs — which only
        // reads on a dark ground. Without this the window chrome would follow the system and go
        // light around dark content.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
        self.hostingView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        activate()
    }

    private func makeContent(initialStep: OnboardingStep) -> OnboardingView {
        OnboardingView(
            hookInstallation: .shared,
            initialStep: initialStep,
            onComplete: { [weak self] in
                self?.complete()
            }
        )
    }

    private func complete() {
        window?.orderOut(nil)
        onCompletion?()
        onCompletion = nil
        // Settings is where a replayed tour is started from, and it needs the app to stay a
        // regular one to keep taking key input.
        if !SettingsWindowController.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
