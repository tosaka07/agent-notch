import SwiftUI

/// The notch silhouette.
///
/// The top edge flares outward toward the menu bar with inner curves (the base of the
/// physical notch); the bottom uses Apple's **continuous rounded corners** (squircle).
///
/// Drawing the bottom corners as circular arcs via `addQuadCurve` would not match the
/// cards that use `DSShape.rounded`, putting two kinds of rounded corner on the same
/// screen — and the panel's radius of 24 is the largest in the app, so the mismatch is
/// the most visible one. Take the real curves from SwiftUI's
/// `UnevenRoundedRectangle(style: .continuous)`; any hand-rolled approximation would be
/// off in its own way.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    /// The body below the top inner curves. Owns the side walls and the bottom rounded corners.
    static func bodyRect(in rect: CGRect, topCornerRadius: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX + topCornerRadius,
            y: rect.minY + topCornerRadius,
            width: max(0, rect.width - 2 * topCornerRadius),
            height: max(0, rect.height - topCornerRadius)
        )
    }

    func path(in rect: CGRect) -> Path {
        let body = Self.bodyRect(in: rect, topCornerRadius: topCornerRadius)
        var p = Path()

        // Trace the complete silhouette as one contour. Liquid Glass treats every
        // closed subpath as a surface boundary; closing the body separately would
        // make its top edge appear as a bright horizontal seam during morphing.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY),
            control: CGPoint(x: body.maxX, y: rect.minY)
        )

        for element in NotchGlowBorder.openBodyElements(
            body,
            bottomCornerRadius: bottomCornerRadius
        ) {
            switch element {
            case .move: break
            case .line(let to): p.addLine(to: to)
            case .quadCurve(let to, let control): p.addQuadCurve(to: to, control: control)
            case .curve(let to, let control1, let control2):
                p.addCurve(to: to, control1: control1, control2: control2)
            case .closeSubpath: break
            }
        }

        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: body.minX, y: rect.minY)
        )
        p.closeSubpath()

        return p
    }
}
