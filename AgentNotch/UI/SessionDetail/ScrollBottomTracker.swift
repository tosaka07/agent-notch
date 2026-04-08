import SwiftUI

/// ViewModifier that tracks whether a ScrollView is scrolled to the bottom.
/// Uses onScrollGeometryChange on macOS 15+, falls back to always-at-bottom on older versions.
struct ScrollBottomTracker: ViewModifier {
    @Binding var isAtBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 40
                } action: { _, newValue in
                    isAtBottom = newValue
                }
        } else {
            content
                .onAppear { isAtBottom = true }
        }
    }
}
