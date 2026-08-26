import SwiftUI

/// Centralizes how corner radii are built.
///
/// # Why this is a token
/// SwiftUI's `RoundedRectangle(cornerRadius:)` and `Shape.rect(cornerRadius:)` **default to
/// `.circular`** (true circular arcs), not the `.continuous` squircle Apple uses in UI. Omitting
/// `style:` is not a type error, so writing them bare guarantees misses — and mixed corner
/// curvature within a single screen.
///
/// **Do not write `RoundedRectangle` / `.rect(cornerRadius:)` directly; go through here.**
///
/// Radius follows surface size, shrinking in the order panel > card > surface > badge.
enum DSShape {
    // MARK: - Radii

    /// Cards inside the panel (approval / question / usage sections).
    static let card: CGFloat = 16
    /// Session cards. One step smaller than a card, showing they line up within the panel.
    static let cell: CGFloat = 14
    /// Surfaces inside a card (command blocks, option rows, buttons).
    static let inset: CGFloat = 8
    /// Restrained enclosures such as collapsible rows and code blocks.
    static let subtle: CGFloat = 6
    /// Badges of one to a few characters (BASH / PLAN / multi-select, etc.).
    static let badge: CGFloat = 4
    /// Even smaller than a badge.
    static let tag: CGFloat = 3

    // MARK: - Shapes

    /// A `.continuous` rounded rectangle. Use instead of `RoundedRectangle`.
    static func rounded(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// A `.continuous` pill. Use instead of `Capsule()`.
    static var pill: Capsule { Capsule(style: .continuous) }
}
