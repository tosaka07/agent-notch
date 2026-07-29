import Foundation
import Testing

@testable import AgentNotch

@Suite("NotchGeometry Tests")
struct NotchGeometryTests {
    let geometry = NotchGeometry(
        notchSize: CGSize(width: 224, height: 38),
        screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
    )

    @Test("notchScreenRect is centered at the top of the screen")
    func notchScreenRectCentering() {
        let rect = geometry.notchScreenRect
        // Centered horizontally
        let expectedX = (1728.0 - 224.0) / 2.0
        #expect(abs(rect.origin.x - expectedX) < 0.01)
        // At top of screen
        let expectedY = 1117.0 - 38.0
        #expect(abs(rect.origin.y - expectedY) < 0.01)
        // Correct size
        #expect(abs(rect.width - 224) < 0.01)
        #expect(abs(rect.height - 38) < 0.01)
    }

    @Test("isPointInNotch returns true for point inside notch")
    func pointInsideNotch() {
        let center = CGPoint(
            x: geometry.notchScreenRect.midX,
            y: geometry.notchScreenRect.midY
        )
        #expect(geometry.isPointInNotch(center))
    }

    @Test("isPointInNotch returns false for point far outside notch")
    func pointOutsideNotch() {
        let farAway = CGPoint(x: 0, y: 0)
        #expect(!geometry.isPointInNotch(farAway))
    }

    @Test("isPointInNotch respects padding")
    func pointInPadding() {
        // Point just outside the notch rect but within padding
        let rect = geometry.notchScreenRect
        let pointInHorizontalPadding = CGPoint(
            x: rect.minX - 5,
            y: rect.midY
        )
        #expect(geometry.isPointInNotch(pointInHorizontalPadding))
    }

    @Test("windowFrame compact width equals notch width + 400")
    func compactWindowFrameWidth() {
        let frame = geometry.windowFrame(isExpanded: false)
        #expect(abs(frame.width - 624) < 0.01)
    }

    @Test("windowFrame expanded uses specified dimensions")
    func expandedWindowFrame() {
        let frame = geometry.windowFrame(
            expandedWidth: 650,
            expandedHeight: 500,
            isExpanded: true
        )
        #expect(abs(frame.width - 650) < 0.01)
        #expect(abs(frame.height - 500) < 0.01)
        // Centered
        let expectedX = (1728.0 - 650.0) / 2.0
        #expect(abs(frame.origin.x - expectedX) < 0.01)
    }
}
