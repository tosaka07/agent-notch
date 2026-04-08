import SwiftUI

/// Mask that keeps only the area OUTSIDE the notch shape.
/// Used with eoFill to clip CompletionFlare so glow only appears on the exterior.
struct NotchOuterMask: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Outer rect covering glow bleed area
        path.addRect(rect.insetBy(dx: -60, dy: -60))
        // Inner notch — with eoFill, overlapping region is cut out
        path.addPath(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            ).path(in: rect)
        )
        return path
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }
}
