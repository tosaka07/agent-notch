import CoreGraphics
import SwiftUI
import Testing

@testable import AgentNotch

/// The notch silhouette is drawn by two shapes: `NotchShape` (the fill) and
/// `NotchGlowBorder` (the completion glow). **If they disagree, the glow drifts off
/// the panel edge**, so these tests pin the geometric assumptions numerically.
///
/// The bottom corner radii come straight from SwiftUI's
/// `UnevenRoundedRectangle(style: .continuous)`, and **its element order is an
/// implementation detail**. If an OS update changes it, the re-stitching in
/// `openBodyElements` breaks — these tests catch that.
@Suite("Notch Shape Tests")
@MainActor
struct NotchShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 620, height: 500)
    private let topRadius: CGFloat = 12
    private let bottomRadius: CGFloat = 24

    private var body: CGRect {
        NotchShape.bodyRect(in: rect, topCornerRadius: topRadius)
    }

    @Test("The silhouette stays inside the given rect")
    func shapeStaysInsideRect() {
        let path = NotchShape(
            topCornerRadius: topRadius,
            bottomCornerRadius: bottomRadius
        ).path(in: rect)

        #expect(!path.isEmpty)
        let box = path.boundingRect
        #expect(box.minX >= rect.minX - 0.01)
        #expect(box.minY >= rect.minY - 0.01)
        #expect(box.maxX <= rect.maxX + 0.01)
        #expect(box.maxY <= rect.maxY + 0.01)
        // The top band spans the full width and the body reaches the bottom, so it
        // effectively fills the whole rect.
        #expect(abs(box.width - rect.width) < 0.5)
        #expect(abs(box.height - rect.height) < 0.5)
    }

    @Test("The silhouette is one closed contour")
    func shapeUsesOneClosedContour() {
        let path = NotchShape(
            topCornerRadius: topRadius,
            bottomCornerRadius: bottomRadius
        ).path(in: rect)
        var moveCount = 0
        var closeCount = 0
        // `Path` is not a Sequence; `forEach(_:)` is its element-visiting API.
        // swift-format-ignore: ReplaceForEachWithForLoop
        path.forEach { element in
            if case .move = element { moveCount += 1 }
            if case .closeSubpath = element { closeCount += 1 }
        }

        // Liquid Glass highlights every closed subpath boundary. A separately
        // closed body would expose its top edge as a bright horizontal seam
        // while the compact shape morphs into the expanded shape.
        #expect(moveCount == 1)
        #expect(closeCount == 1)
    }

    /// The top inner curve insets by `topCornerRadius`. If that changes, the shape
    /// no longer meets the base of the physical notch.
    @Test("The body is inset by the top inner curve")
    func bodyRectIsInsetByTopRadius() {
        #expect(body.minX == rect.minX + topRadius)
        #expect(body.minY == rect.minY + topRadius)
        #expect(body.width == rect.width - 2 * topRadius)
        #expect(body.maxY == rect.maxY)
    }

    /// The glow border must trace the same outline minus the top edge: starting at
    /// the top-right (body.maxX, body.minY) and ending at the top-left
    /// (body.minX, body.minY).
    @Test("The glow border runs unbroken from top-right to top-left")
    func glowBorderRunsFromTopRightToTopLeft() {
        let elements = NotchGlowBorder.openBodyElements(body, bottomCornerRadius: bottomRadius)
        #expect(!elements.isEmpty)

        // No subpath break during re-stitching (a break would make the line jump).
        let hasMove = elements.contains { if case .move = $0 { return true } else { return false } }
        #expect(!hasMove)

        // The final point lands at the top-left.
        var last: CGPoint?
        for element in elements {
            switch element {
            case .line(let to), .quadCurve(let to, _), .curve(let to, _, _): last = to
            default: break
            }
        }
        #expect(last != nil)
        #expect(abs((last?.x ?? .nan) - body.minX) < 0.5)
        #expect(abs((last?.y ?? .nan) - body.minY) < 0.5)
    }

    @Test("The glow border never runs along the top edge")
    func glowBorderSkipsTopEdge() {
        let elements = NotchGlowBorder.openBodyElements(body, bottomCornerRadius: bottomRadius)
        // A horizontal segment along the top edge would put a glow at the screen edge.
        let hasTopEdge = elements.contains { element in
            guard case .line(let to) = element else { return false }
            return abs(to.y - body.minY) < 0.5 && abs(to.x - body.maxX) < 0.5
        }
        #expect(!hasTopEdge)

        let path = NotchGlowBorder(
            topCornerRadius: topRadius,
            bottomCornerRadius: bottomRadius
        ).path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.maxX <= rect.maxX + 0.01)
        #expect(path.boundingRect.maxY <= rect.maxY + 0.01)
    }

    /// `notchBlackout` has no top inner curve — it touches the screen edge, so none is needed.
    @Test("With a zero top inner curve, the body fills the whole rect")
    func zeroTopRadiusFillsRect() {
        let flat = NotchShape.bodyRect(in: rect, topCornerRadius: 0)
        #expect(flat == rect)

        let path = NotchShape(topCornerRadius: 0, bottomCornerRadius: 14).path(in: rect)
        #expect(abs(path.boundingRect.width - rect.width) < 0.5)
        #expect(abs(path.boundingRect.height - rect.height) < 0.5)
    }
}
