import SwiftUI

/// The **role** of a surface placed inside the panel.
///
/// # Why roles rather than values
/// Writing surfaces as "black 52%" or "white 6%" makes surfaces with the same role come out at
/// different strengths in different places — one block ends up a flat `Color.black` while the
/// code block next to it is material, and their textures no longer match.
/// **State what the surface is, not how to paint it**, and keep the recipe in one place.
///
/// # Why material
/// The panel is Liquid Glass and the background pattern shows through, so a surface built from
/// brightness alone drowns in the pattern. Material blurs what is behind it, so the surface's
/// outline reads no matter what is back there. Flat black, by contrast, looks heavy — like a
/// hole punched in the panel.
///
/// # Hierarchy
/// ```
/// Panel (glass)
///   └ panelCard … content card following the panel's backdrop
///       ├ raised  … pressable surface. In front of the card (add white)
///       └ inset   … value-showing surface. Behind the card (add black)
/// ```
enum DSSurface {
    /// Content cards placed directly on the glass panel.
    case panelCard
    /// Value-showing surfaces: commands, tool output, diffs, code blocks.
    /// They are read, not touched, so they sit one step back toward the background.
    case inset
    /// Pressable surfaces: question options, notification rows.
    /// A sunken surface does not invite a touch, so it is lifted one step.
    case raised
    /// A pressable surface that is currently selected.
    case raisedSelected
    /// A pressable surface with the pointer over it.
    case raisedHover
    /// An accessory floating **outside** the panel, directly over the wallpaper (the completion
    /// pill, etc.). With no panel scrim underneath it, it uses a stronger scrim than raised so
    /// text stays readable on its own.
    case floating
    /// A control pinned above scrolling content.
    ///
    /// Reads as a sibling of the panel's system buttons — the tint is the fill AppKit paints
    /// for `.bordered` (`DSColors.control`) — but that fill alone is nearly transparent, and a
    /// control anchored over a moving log has to blur what travels underneath rather than let
    /// the text read straight through it.
    case control

    /// Strength of the scrim that damps the material's whiteness.
    fileprivate var scrimOpacity: Double {
        switch self {
        case .panelCard: DSColors.panelCardScrimOpacity
        case .inset: DSColors.insetScrimOpacity
        case .raised, .raisedSelected, .raisedHover: DSColors.raisedScrimOpacity
        case .floating: DSColors.cardScrimOpacity
        case .control: 0
        }
    }

    /// White added to bring the surface forward. `inset` adds none, since it should recede.
    fileprivate var lift: Color {
        switch self {
        case .panelCard, .inset, .floating: .clear
        case .raised: DSColors.surface
        case .raisedHover: DSColors.surface
        case .raisedSelected: DSColors.surfaceStrong
        case .control: DSColors.control
        }
    }

    /// The substitute under Reduce Transparency: drop the material and build hierarchy from
    /// brightness alone.
    fileprivate var opaqueTint: Color {
        switch self {
        case .panelCard: DSColors.surface
        case .inset, .floating: DSColors.canvas
        case .raised, .raisedHover: DSColors.surface
        case .raisedSelected: DSColors.surfaceStrong
        case .control: DSColors.control
        }
    }
}

/// Draws a `DSSurface` as an actual surface. Pass it to `.background(...)`.
///
/// Clipping and the border are the caller's responsibility, since both the corner radius and the
/// border's semantic color vary per surface.
struct DSSurfaceFill: View {
    let surface: DSSurface

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(_ surface: DSSurface) {
        self.surface = surface
    }

    var body: some View {
        if reduceTransparency {
            surface.opaqueTint.background(DSColors.canvas)
        } else {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(DSColors.canvas.opacity(surface.scrimOpacity))
                .overlay(surface.lift)
        }
    }
}
