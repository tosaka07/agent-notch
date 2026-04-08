import SwiftUI

/// NotchShape without the top edge — for border glow that doesn't show along the screen top.
struct NotchGlowBorder: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = topCornerRadius
        let br = bottomCornerRadius
        var p = Path()

        // Start from top-right (after curve), trace down and around to top-left
        // Skip the top edge entirely
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.maxY - br),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + tr, y: rect.minY)
        )
        // Do NOT close — leaves the top edge open
        return p
    }
}
