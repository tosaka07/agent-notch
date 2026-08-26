import Defaults
import SwiftUI

enum PanelScrimPolicy {
    static func opacity(showsSurface: Bool) -> Double {
        showsSurface ? DSColors.glassPanelScrimOpacity : 1
    }
}

/// ViewModifier that applies the notch shell in one place — size, shape clip,
/// glass, glow overlay, hover, mode animation — so pages only deal with content.
struct NotchShell: ViewModifier {
    let viewModel: NotchViewModel
    let glow: CompletionGlowController

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var presentedMetrics: NotchSurfaceMetrics
    /// Namespace that tells SwiftUI the glass keeps its identity.
    ///
    /// `NotchRootView` rebuilds its content with a `switch` per mode, so without
    /// a fixed ID the glass could be recreated as a different view on every
    /// transition. One ID is enough — splitting it per mode makes the glass
    /// materialize again each time and flicker.
    @Namespace private var glassNamespace

    init(viewModel: NotchViewModel, glow: CompletionGlowController) {
        self.viewModel = viewModel
        self.glow = glow
        self._presentedMetrics = State(
            initialValue: NotchSurfaceMetrics(
                width: viewModel.notchWidth,
                height: viewModel.notchHeight,
                topCornerRadius: viewModel.topCornerRadius,
                bottomCornerRadius: viewModel.bottomCornerRadius
            )
        )
    }

    private var targetMetrics: NotchSurfaceMetrics {
        NotchSurfaceMetrics(
            width: viewModel.notchWidth,
            height: viewModel.notchHeight,
            topCornerRadius: viewModel.topCornerRadius,
            bottomCornerRadius: viewModel.bottomCornerRadius
        )
    }

    private var currentShape: CenteredNotchShape {
        presentedMetrics.shape
    }

    /// Whether the glass should be see-through.
    ///
    /// `compact` matches the notch exactly, so it is always opaque black and
    /// overlaps the physical notch perfectly. Every other mode extends below the
    /// notch and is therefore translucent: the glass appears to surround the
    /// black notch, making the panel look like it grew out of it.
    private var showsSurface: Bool {
        guard !reduceTransparency else { return false }
        return viewModel.mode != .compact
    }

    /// Layer that fills in only the part overlapping the physical notch.
    ///
    /// The screen is physically black here, so any translucency exposes the seam
    /// with the notch and makes the panel look detached. Whenever glass or a
    /// light scrim is in play, this region is blacked out separately so it reads
    /// as continuous with the hardware.
    ///
    /// **The shape must follow the notch silhouette.** A plain rectangle leaves
    /// square bottom corners, and the angular black floats inside the rounded
    /// physical notch. The top edge meets the screen border so it needs no
    /// rounding; only the bottom uses the notch's own radius — not the panel's.
    private var notchBlackout: some View {
        Color.clear.overlay(alignment: .top) {
            NotchShape(
                topCornerRadius: 0,
                bottomCornerRadius: viewModel.physicalNotchCornerRadius
            )
            .fill(Color.black)
            .frame(
                width: viewModel.physicalNotchWidth,
                height: viewModel.physicalNotchHeight
            )
        }
    }

    /// Keeps compact opaque and blacks out only the physical-notch region when
    /// the panel is glass.
    private var panelScrim: some View {
        Color.black
            .opacity(PanelScrimPolicy.opacity(showsSurface: showsSurface))
            .overlay {
                notchBlackout.opacity(showsSurface ? 1 : 0)
            }
    }

    /// Covers the glass highlight at the screen-aligned top edge.
    private var topEdgeCap: some View {
        Color.clear
            .frame(
                width: NotchPresentationLayout.stageSize.width,
                height: NotchPresentationLayout.stageSize.height
            )
            .overlay(alignment: .top) {
                Color.black
                    .opacity(showsSurface ? 1 : 0)
                    .frame(
                        width: presentedMetrics.width,
                        height: 1 / max(displayScale, 1)
                    )
            }
            .allowsHitTesting(false)
    }

    /// Gives the panel its surface.
    ///
    /// # Apply `glassEffect` directly to the content
    /// Following Apple's guide (Applying Liquid Glass to custom views),
    /// **`glassEffect(in:)` goes after the appearance modifiers**. Laying a
    /// `Rectangle().glassEffect()` down as a background is not a supported use:
    /// when the size changes on a mode transition, it freezes having lost its
    /// translucency.
    ///
    /// No tint. Tint is for drawing attention, not for darkening — the darkness
    /// comes from the `panelScrim` underneath.
    ///
    /// No border. Liquid Glass already outlines itself through the refracted
    /// background brightening at the edge; a hand-drawn stroke on top only
    /// muddies it.
    ///
    /// When "Reduce transparency" is on, **drop the glass entirely**. Falling
    /// back to a material would still be see-through, which fails to honor the
    /// setting.
    @ViewBuilder
    private func withSurface(_ view: some View) -> some View {
        if reduceTransparency {
            view
                .background(DSColors.canvas)
                .clipShape(currentShape)
        } else {
            view
                .glassEffect(.regular, in: currentShape)
                .glassEffectID(GlassID.panel, in: glassNamespace)
        }
    }

    /// Identifier passed to `glassEffectID`. Exists only to rule out typos in a
    /// string literal.
    private enum GlassID: Hashable, Sendable {
        case panel
    }

    /// Animation for mode transitions.
    ///
    /// Opening feels good with a little spring overshoot, but **closing must not
    /// overshoot**. Dipping momentarily below the compact size lets the
    /// background peek through the physical notch edge, so the panel appears to
    /// shrink and snap back. Closing therefore lands critically damped.
    private var modeAnimation: Animation? {
        NotchPresentationAnimation.animation(
            expanding: viewModel.mode.isFullPanel,
            reduceMotion: reduceMotion
        )
    }

    private var hoverAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.3, dampingFraction: 0.7)
    }

    /// Keeps the page at its destination size while only the centered surface
    /// shape animates. This prevents every session row from being measured at
    /// every intermediate shell width.
    private func fixedStageContent(_ content: Content) -> some View {
        ZStack(alignment: .top) {
            panelScrim

            content
                .frame(
                    width: targetMetrics.width,
                    height: targetMetrics.height,
                    alignment: .top
                )
                // Page identity changes immediately. The separate
                // `presentedMetrics` transaction below animates only the shell.
                .transaction(value: viewModel.mode) { $0.animation = nil }
                // Hover must belong to the destination-sized panel, not the
                // fixed 640×520 stage around it. Otherwise leaving the visible
                // compact surface still counts as hovering over transparent
                // stage space and the expanded hover size never collapses.
                .onHover { hovering in
                    guard viewModel.mode == .compact else { return }
                    withAnimation(hoverAnimation) {
                        viewModel.isHovering = hovering
                    }
                }
        }
        .frame(
            width: NotchPresentationLayout.stageSize.width,
            height: NotchPresentationLayout.stageSize.height,
            alignment: .top
        )
        .clipShape(currentShape)
    }

    /// Completion glow remains a separate, non-glass layer. It may resize,
    /// because changing its bounds cannot destabilize the Liquid Glass surface.
    private var completionFlare: some View {
        CompletionFlare(
            shape: NotchGlowBorder(
                topCornerRadius: presentedMetrics.topCornerRadius,
                bottomCornerRadius: presentedMetrics.bottomCornerRadius
            ),
            color: glow.color,
            intensity: glow.intensity
        )
        .frame(width: presentedMetrics.width, height: presentedMetrics.height)
        .clipShape(
            NotchOuterMask(
                topCornerRadius: presentedMetrics.topCornerRadius,
                bottomCornerRadius: presentedMetrics.bottomCornerRadius
            ),
            style: FillStyle(eoFill: true)
        )
        .frame(
            width: NotchPresentationLayout.stageSize.width,
            height: NotchPresentationLayout.stageSize.height,
            alignment: .top
        )
        .allowsHitTesting(false)
    }

    /// # Never place a rasterization-inducing modifier outside the glass
    ///
    /// Applying `clipShape` / `shadow` / `mask` / `opacity` **after**
    /// `glassEffect` makes SwiftUI render into an offscreen buffer, baking the
    /// glass background of that instant into it. That is why translucency gets
    /// stuck every time a mode transition recreates the buffer.
    ///
    /// Therefore:
    /// - Do `clipShape` **inside** the glass, on the content. `glassEffect(in:)`
    ///   carries the same shape, so the result looks identical.
    /// - No `shadow`. Liquid Glass provides its own shadow and depth.
    /// - `overlay` is safe: it only adds a sibling layer. Clipping the overlay's
    ///   **contents** is fine.
    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: 0) {
            withSurface(fixedStageContent(content))
        }
        .frame(
            width: NotchPresentationLayout.stageSize.width,
            height: NotchPresentationLayout.stageSize.height,
            alignment: .top
        )
        .overlay(alignment: .top) {
            topEdgeCap
        }
        .overlay(completionFlare)
        // No shadow: `shadow` forces the glass offscreen and bakes in its
        // translucency. Liquid Glass carries its own shadow and depth
        // anyway, so there is nothing to add from outside.
        .contentShape(currentShape)
        // When another session finishes in the background while a full panel
        // (expanded / sessionDetail) is up, the outline glows but gives no
        // clue which session it was — so a completion pill appears briefly.
        //
        // The pill hangs **outside the panel, below it**. Overlaying it
        // inside (top-right, say) would collide with the top bar's buttons.
        // An overlay is a sibling layer, so it does not run into the
        // glassEffect rasterization constraint. It goes **after**
        // `contentShape(currentShape)` so it never disturbs the panel's hit
        // region.
        //
        // Its position is declared with alignmentGuide rather than an offset
        // ("pill top = panel bottom + gap"). The inner frame follows the
        // animated surface height while the outer stage stays fixed.
        .overlay(alignment: .top) {
            if viewModel.mode.isFullPanel, let pill = glow.pill {
                Color.clear
                    .frame(width: presentedMetrics.width, height: presentedMetrics.height)
                    .overlay(alignment: .bottom) {
                        CompletionPillView(pill: pill, color: glow.color) {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                                viewModel.showSession(pill.sessionId)
                            }
                            glow.cancel()
                        }
                        .alignmentGuide(.bottom) { d in d[.top] - DSSpacing.sm }
                        // Report the height hanging below the panel to the view
                        // model so HotZoneTracker's outside-click test (which
                        // closes the panel) includes the pill.
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                            viewModel.bottomAccessoryHeight = $0 + DSSpacing.sm
                        }
                        .onDisappear { viewModel.bottomAccessoryHeight = 0 }
                        .transition(.opacity)
                    }
                    .frame(
                        width: NotchPresentationLayout.stageSize.width,
                        height: NotchPresentationLayout.stageSize.height,
                        alignment: .top
                    )
            }
        }
        .onChange(of: targetMetrics) { _, target in
            withAnimation(modeAnimation) {
                presentedMetrics = target
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Applies the notch shell: size, shape, glow, shadow, hover, mode animation.
    func notchShell(viewModel: NotchViewModel, glow: CompletionGlowController) -> some View {
        modifier(NotchShell(viewModel: viewModel, glow: glow))
    }
}
