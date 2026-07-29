import SwiftUI

/// Tracks whether the inverted newest-first log is at its logical origin.
struct ScrollNewestTracker: ViewModifier {
    @Binding var isAtNewest: Bool

    /// A row's padding is a few points, so this absorbs a nudge without
    /// unlatching automatic following.
    private static let tolerance: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y <= Self.tolerance
            } action: { _, newValue in
                isAtNewest = newValue
            }
    }
}
