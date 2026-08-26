import SwiftUI

/// A miniature of the compact notch, shown inside the onboarding window.
///
/// The tour explains the notch, so it shows the notch rather than describing it. The silhouette
/// comes from `NotchShape` and the wings from `StateGlyphView` / `PixelCounter` — the same views
/// `CompactPageView` renders on screen — so this preview cannot drift away from the real display.
///
/// The wing geometry mirrors `NotchViewModel`: glyphs only, no text, with an `edgeMargin` keeping
/// the drawing area inside what the notch's rounded corners leave visible.
struct OnboardingNotchPreview: View {
    let state: Glyph.State
    /// Running / total for the right wing. nil leaves the wing empty, which is what compact mode
    /// shows before any session exists — a `0/0` counter would claim a session is being tracked.
    var counter: (running: Int, total: Int)?

    /// The real physical notch is 224×38 on a 14"/16" MacBook Pro; the preview keeps that
    /// proportion so what the user sees here matches what appears at the top of the screen.
    private let notchWidth: CGFloat = 224
    private let notchHeight: CGFloat = 34
    private let wing: CGFloat = 62
    private let edgeMargin: CGFloat = 8

    private var wingInner: CGFloat { max(0, wing - edgeMargin) }

    var body: some View {
        // Stands in for the top edge of the screen. The notch is black, so without a surface
        // behind it the silhouette has no edge on a dark window and the shape does not read.
        // A neutral hierarchy fill, not a tinted wallpaper gradient: this is a diagram of where
        // the notch sits, and a colored slab in the middle of the page only looked like an
        // artifact.
        UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9, style: .continuous)
            .fill(.quinary)
            .frame(height: notchHeight + 16)
            .overlay(alignment: .top) { notch }
            .accessibilityElement()
            .accessibilityLabel(L("Preview of the notch display"))
    }

    private var notch: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: edgeMargin)

            StateGlyphView(state: state, size: min(wingInner, notchHeight - 12))
                .frame(width: wingInner, height: notchHeight)

            // The center overlaps the physical notch, where nothing is visible, so nothing is
            // drawn there — exactly as in compact mode.
            Color.clear.frame(width: notchWidth, height: notchHeight)

            ZStack {
                if let counter {
                    PixelCounter(
                        value: counter.running,
                        total: counter.total,
                        valueColor: DSColors.ink,
                        totalColor: DSColors.ink.opacity(0.55)
                    )
                }
            }
            .frame(width: wingInner, height: notchHeight)

            Color.clear.frame(width: edgeMargin)
        }
        .frame(height: notchHeight)
        .background(DSColors.canvas)
        .clipShape(NotchShape(topCornerRadius: 0, bottomCornerRadius: 13))
    }
}

#Preview("Onboarding Notch Preview") {
    VStack(spacing: 20) {
        OnboardingNotchPreview(state: .thinking, counter: (running: 3, total: 7))
        OnboardingNotchPreview(state: .standby)
    }
    .padding(24)
    .background(Color(red: 0.055, green: 0.055, blue: 0.063))
}
