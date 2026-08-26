import SwiftUI

/// Draws the notch surface inside a fixed stage.
///
/// The stage keeps the Liquid Glass view's bounds stable. Only this shape's
/// sub-rectangle changes, so a width transition expands equally toward the
/// leading and trailing edges instead of moving the glass-bearing view.
struct CenteredNotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    typealias AnimatableData = AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    >

    var animatableData: AnimatableData {
        get {
            .init(
                .init(width, height),
                .init(topCornerRadius, bottomCornerRadius)
            )
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            topCornerRadius = newValue.second.first
            bottomCornerRadius = newValue.second.second
        }
    }

    /// The visible surface rectangle, centered horizontally and pinned to the
    /// screen-aligned top edge of the fixed stage.
    func surfaceRect(in stage: CGRect) -> CGRect {
        let resolvedWidth = min(max(0, width), stage.width)
        let resolvedHeight = min(max(0, height), stage.height)
        return CGRect(
            x: stage.midX - resolvedWidth / 2,
            y: stage.minY,
            width: resolvedWidth,
            height: resolvedHeight
        )
    }

    func path(in rect: CGRect) -> Path {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
        .path(in: surfaceRect(in: rect))
    }
}
