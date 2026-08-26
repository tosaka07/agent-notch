import SwiftUI

/// The notch silhouette without its top edge, so the completion glow does not run along
/// the top of the screen.
///
/// **The curves come from `NotchShape`.** Its bottom corners are continuous rounded
/// corners; drawing the same shape a second way here would put the glow a few pixels off
/// the panel edge. Instead, take `NotchShape`'s path and drop only the top edge to get an
/// open outline.
struct NotchGlowBorder: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let body = NotchShape.bodyRect(in: rect, topCornerRadius: topCornerRadius)

        var p = Path()
        // Top-right inner curve, from the menu bar side into the body.
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY),
            control: CGPoint(x: body.maxX, y: rect.minY)
        )
        // Trace the body outline from top-right to top-left, skipping the top edge.
        // The current point is at (body.maxX, body.minY) and we append to it, so `addPath`
        // is not used — it would start a new subpath and break the line.
        for element in Self.openBodyElements(body, bottomCornerRadius: bottomCornerRadius) {
            switch element {
            case .move: break
            case .line(let to): p.addLine(to: to)
            case .quadCurve(let to, let control): p.addQuadCurve(to: to, control: control)
            case .curve(let to, let control1, let control2):
                p.addCurve(to: to, control1: control1, control2: control2)
            case .closeSubpath: break
            }
        }
        // Top-left inner curve.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: body.minX, y: rect.minY)
        )
        // Left open, so there is no top edge.
        return p
    }

    /// Returns an open outline of a rectangle with continuous bottom corners, **with only
    /// the top edge removed**.
    ///
    /// To use SwiftUI's real corner curves instead of approximating them, this walks the
    /// elements `UnevenRoundedRectangle` emits and cuts at the top edge (the horizontal
    /// line whose endpoints both sit at y == minY). `UnevenRoundedRectangle` starts partway
    /// down the right side and goes clockwise, so joining the two resulting runs as
    /// "second, then first" yields a single outline running top-right to top-left.
    ///
    /// The element order is a SwiftUI implementation detail, so `NotchGlowBorderTests`
    /// verifies the start point, end point, and bounds — it will fail if an OS update
    /// changes the order.
    static func openBodyElements(_ rect: CGRect, bottomCornerRadius: CGFloat) -> [Path.Element] {
        let closed = UnevenRoundedRectangle(
            bottomLeadingRadius: bottomCornerRadius,
            bottomTrailingRadius: bottomCornerRadius,
            style: .continuous
        )
        .path(in: rect)

        let epsilon: CGFloat = 0.5
        func isOnTopEdge(_ point: CGPoint) -> Bool { abs(point.y - rect.minY) < epsilon }

        var segments: [[Path.Element]] = [[]]
        var cursor = CGPoint.zero
        var subpathStart = CGPoint.zero

        // `Path` is not a Sequence; `forEach(_:)` is its only element-visiting API.
        // swift-format-ignore: ReplaceForEachWithForLoop
        closed.forEach { element in
            switch element {
            case .move(let to):
                cursor = to
                subpathStart = to
            case .line(let to):
                if isOnTopEdge(cursor), isOnTopEdge(to) {
                    segments.append([])  // Drop the top edge and cut here.
                } else {
                    segments[segments.count - 1].append(element)
                }
                cursor = to
            case .quadCurve(let to, _), .curve(let to, _, _):
                segments[segments.count - 1].append(element)
                cursor = to
            case .closeSubpath:
                // Treat the closing edge as a cut too when it lies on the top edge.
                if isOnTopEdge(cursor), isOnTopEdge(subpathStart) {
                    segments.append([])
                } else {
                    segments[segments.count - 1].append(.line(to: subpathStart))
                }
                cursor = subpathStart
            }
        }

        let ordered = segments.filter { !$0.isEmpty }
        guard ordered.count > 1 else { return ordered.first ?? [] }
        return ordered.dropFirst().flatMap { $0 } + ordered[0]
    }
}
