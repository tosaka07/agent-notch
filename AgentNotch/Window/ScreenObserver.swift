import AppKit

@MainActor
final class ScreenObserver {
    var onScreenChanged: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screenDidChange(_ notification: Notification) {
        onScreenChanged?()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
