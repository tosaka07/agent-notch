import AppKit
import SwiftUI

/// NSHostingView that only accepts clicks within a dynamic hit-test rectangle.
/// Clicks outside the rect pass through to windows behind, as if this view doesn't exist.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Returns the current hit-testable rect in the view's local coordinate system.
    /// Clicks outside this rect return nil from hitTest, making them pass through.
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestRect().contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
