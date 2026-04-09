import AppKit
import SwiftUI

/// Simple NSHostingView subclass. clipShape on the SwiftUI side controls hit testing.
/// No hitTestRect or ignoresMouseEvents toggling needed.
final class NotchHostingView<Content: View>: NSHostingView<Content> {}
