import AppKit
import SwiftUI

/// Simple NSHostingView subclass. clipShape on the SwiftUI side controls hit testing.
/// No hitTestRect or ignoresMouseEvents toggling needed.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Let the very first click fire SwiftUI actions even while the panel is not the key
    /// window — the normal case, since another app is active. With the default (false),
    /// the first click is consumed making the window key and a button's action does not
    /// arrive until the second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Take the window's full bounds, ignoring safe areas.
        //
        // The panel deliberately covers the menu bar and the physical notch, but
        // NSHostingView still hands SwiftUI the screen's safe-area insets, so the
        // content is nudged down from the window's top edge and a sliver of desktop
        // shows above the panel.
        safeAreaRegions = []
    }

    @MainActor @preconcurrency
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        safeAreaRegions = []
    }
}
