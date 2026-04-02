import AppKit

extension NSScreen {
    /// Whether this screen is the built-in display (e.g., MacBook's internal screen).
    @MainActor
    var isBuiltinDisplay: Bool {
        let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        guard let cgDirectDisplayID = screenNumber as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(cgDirectDisplayID) != 0
    }

    /// Whether this screen has a physical notch (safe area insets at top > 0).
    @MainActor
    var hasPhysicalNotch: Bool {
        if #available(macOS 14.0, *) {
            return safeAreaInsets.top > 0
        }
        return false
    }

    /// The size of the notch area. Uses auxiliary top-left/right areas when available,
    /// otherwise falls back to a default size matching the MacBook Pro notch.
    @MainActor
    var notchSize: CGSize {
        guard hasPhysicalNotch else {
            return CGSize(width: 224, height: 38)
        }

        if #available(macOS 14.0, *) {
            let topInset = safeAreaInsets.top
            let leftWidth = auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = auxiliaryTopRightArea?.width ?? 0

            // Notch width = screen width - left auxiliary - right auxiliary
            let notchWidth = frame.width - leftWidth - rightWidth
            let notchHeight = topInset

            if notchWidth > 0 && notchHeight > 0 {
                return CGSize(width: notchWidth, height: notchHeight)
            }
        }

        return CGSize(width: 224, height: 38)
    }

    /// The first built-in screen, or the main screen as fallback.
    @MainActor
    static var builtin: NSScreen? {
        NSScreen.screens.first(where: { $0.isBuiltinDisplay }) ?? NSScreen.main
    }
}
