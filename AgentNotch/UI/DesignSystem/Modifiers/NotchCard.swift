import SwiftUI

/// "A second surface" placed inside the notch panel. Used by the approval / question
/// interruption cards.
///
/// # How the surface is built
/// From the same Liquid Glass recipe as the panel. The outer shell owns the
/// single `GlassEffectContainer`; cards opt out of shape morphing with an
/// identity glass transition.
///
/// **Glass stops here.** Apple's guidance is to avoid layering glass elements on each other, so
/// surfaces inside the card (command blocks, option rows) build hierarchy from the brightness
/// difference of material plus scrim (`DSColors.insetScrimOpacity` / `raisedScrimOpacity`).
///
/// No shadow. Liquid Glass carries its own shadow and depth, and `shadow` forces the glass
/// offscreen and bakes the transparency in (see the comment in `NotchShell.body`).
struct NotchCard: ViewModifier {
    /// The semantic color used for the border (awaiting approval = amber, expired = red).
    var accent: Color
    var cornerRadius: CGFloat = DSShape.card
    /// Optional veil between the sampled backdrop and card content.
    ///
    /// Pinned cards can sit directly above dense log text. A scrim keeps that
    /// text from competing with the card while preserving Liquid Glass's
    /// refraction and edge highlights.
    var scrimOpacity: Double = 0
    var horizontalPadding: CGFloat = DSSpacing.lg
    var verticalPadding: CGFloat = DSSpacing.lg
    /// Cards fill their container by default; compact controls keep their
    /// intrinsic width while using the exact same surface recipe.
    var fillsWidth: Bool = true
    /// Nudges the surface itself slightly toward `accent`.
    ///
    /// An exception to the "signal colors are never used for area" principle. Approval is the
    /// one state where **the agent is stopped until you press**, so it should be noticeable from
    /// the surface, not just the border. Several never appear at once, so there is no risk of
    /// the screen flooding with semantic color.
    var tintsSurface: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        laidOut(content)
            .overlay(
                DSShape.rounded(cornerRadius)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
    }

    /// Applies padding first, then the surface.
    ///
    /// `glassEffect` has to come **after any other modifier that affects appearance**, so do not
    /// break the padding → frame → glassEffect order.
    @ViewBuilder
    private func laidOut(_ content: Content) -> some View {
        let padded =
            content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)

        if fillsWidth {
            surface(padded.frame(maxWidth: .infinity, alignment: .leading))
        } else {
            surface(padded)
        }
    }

    @ViewBuilder
    private func surface<SurfaceContent: View>(_ sized: SurfaceContent) -> some View {
        let scrimmed =
            sized.background {
                DSShape.rounded(cornerRadius)
                    .fill(DSColors.canvas.opacity(scrimOpacity))
            }

        if reduceTransparency {
            // With transparency off, nothing shows through; the brightness difference comes
            // from the surface.
            scrimmed
                .background(
                    DSColors.surfaceStrong
                        .background(DSColors.canvas)
                        .overlay(tintsSurface ? accent.opacity(0.12) : .clear)
                )
                .clipShape(DSShape.rounded(cornerRadius))
        } else {
            // Liquid Glass tint strengthens when the panel becomes key, which made an approval
            // card jump from pale amber to a much denser yellow as soon as keyboard focus moved
            // to it. Keep the glass neutral and paint a fixed, subtle wash above it so semantic
            // color does not change with window focus.
            // `.rect(cornerRadius:)` defaults to `.circular`, so go through DSShape here too.
            scrimmed
                .glassEffect(.regular, in: DSShape.rounded(cornerRadius))
                .overlay {
                    DSShape.rounded(cornerRadius)
                        .fill(tintsSurface ? accent.opacity(0.08) : .clear)
                        // This wash is decoration; the card's controls own pointer input.
                        .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    /// A glass card surface for inside the notch panel — padding, corner radius, and the
    /// semantic border applied together.
    /// Setting `tintsSurface` tints the glass toward `accent` (for cases like approval, where
    /// the surface itself should catch the eye).
    func notchCard(
        accent: Color,
        cornerRadius: CGFloat = DSShape.card,
        scrimOpacity: Double = 0,
        horizontalPadding: CGFloat = DSSpacing.lg,
        verticalPadding: CGFloat = DSSpacing.lg,
        fillsWidth: Bool = true,
        tintsSurface: Bool = false
    ) -> some View {
        modifier(
            NotchCard(
                accent: accent,
                cornerRadius: cornerRadius,
                scrimOpacity: scrimOpacity,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                fillsWidth: fillsWidth,
                tintsSurface: tintsSurface
            )
        )
    }
}
