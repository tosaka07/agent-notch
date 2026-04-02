import SwiftUI

/// A shape that mimics the MacBook notch.
/// Top edge is flat (flush with screen top). Only bottom corners are rounded.
struct NotchShape: Shape {
    var bottomCornerRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let br = bottomCornerRadius

        // Top-left (square corner)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))

        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))

        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Left edge back to top
        path.closeSubpath()
        return path
    }
}
