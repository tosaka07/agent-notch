import SwiftUI

/// The surface of a "content card" placed directly on the panel.
/// Used by session cards, the usage sections, and the daily cost card.
///
/// # Why material
/// A flat +6% white over black is enough to read an edge only while the panel is opaque black.
/// **Once the panel is glass and the background pattern shows through**, a uniform +6%
/// brightness difference drowns in the pattern and the card's outline disappears.
///
/// So the separation is by **texture**, not brightness. Material blurs what is behind it, so no
/// matter what sits back there, "from here on is the card's surface" reads. The scrim only goes
/// as far as damping the material's whiteness; bringing it forward is done with white (`tint`).
///
/// # How this differs from `NotchCard`
/// `NotchCard` is the **interruption** card for approvals and questions, and its surface is
/// Liquid Glass itself. This one is panel content, so it is built from material rather than
/// stacking glass (Apple's guidance is to avoid layering glass elements on each other).
///
/// It adds no padding. How densely packed the contents are varies per card, so that is the
/// caller's responsibility.
struct PanelCard: ViewModifier {
    var cornerRadius: CGFloat = DSShape.card
    /// Surface brightness. `surfaceStrong` while interrupting; fainter to recede.
    var tint: Color = DSColors.surface
    /// The border. **Drawn in the normal state too** — the surface alone does not say where the
    /// card ends, and the rows read as one continuous stretch.
    var border: Color = DSColors.lineDefault

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(surface)
            .clipShape(DSShape.rounded(cornerRadius))
            .overlay(
                // On glass a 0.5px hairline loses to the background pattern, so draw it at 1px.
                DSShape.rounded(cornerRadius).stroke(border, lineWidth: 1)
            )
    }

    /// Uses a lightly damped material that follows the panel's backdrop.
    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            tint.background(DSColors.canvas)
        } else {
            DSSurfaceFill(.panelCard).overlay(tint)
        }
    }
}

extension View {
    /// Applies the content card surface for the panel — material + scrim + brightness + border —
    /// all at once.
    func panelCard(
        cornerRadius: CGFloat = DSShape.card,
        tint: Color = DSColors.surface,
        border: Color = DSColors.lineDefault
    ) -> some View {
        modifier(PanelCard(cornerRadius: cornerRadius, tint: tint, border: border))
    }
}
