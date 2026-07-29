import CoreGraphics
import SwiftUI
import Testing

@testable import AgentNotch

@Suite("Centered notch shape")
@MainActor
struct CenteredNotchShapeTests {
    private let stage = CGRect(x: 40, y: 12, width: 640, height: 520)

    @Test("Compact to expanded keeps the surface centered at every sampled frame")
    func transitionKeepsSurfaceCentered() {
        let compact = CGSize(width: 302, height: 38)
        let expanded = CGSize(width: 520, height: 380)

        for step in 0...120 {
            let progress = CGFloat(step) / 120
            let size = CGSize(
                width: compact.width + (expanded.width - compact.width) * progress,
                height: compact.height + (expanded.height - compact.height) * progress
            )
            let path = CenteredNotchShape(
                width: size.width,
                height: size.height,
                topCornerRadius: 6 + 6 * progress,
                bottomCornerRadius: 14 + 10 * progress
            )
            .path(in: stage)
            let bounds = path.boundingRect

            #expect(abs(bounds.midX - stage.midX) < 0.01)
            #expect(abs(bounds.minX + bounds.maxX - stage.minX - stage.maxX) < 0.01)
            #expect(abs(bounds.minY - stage.minY) < 0.01)
            #expect(abs(bounds.width - size.width) < 0.01)
            #expect(abs(bounds.height - size.height) < 0.01)
        }
    }

    @Test("Surface dimensions are constrained to the fixed stage")
    func surfaceIsConstrainedToStage() {
        let shape = CenteredNotchShape(
            width: 900,
            height: 700,
            topCornerRadius: 12,
            bottomCornerRadius: 24
        )

        #expect(shape.surfaceRect(in: stage) == stage)
        #expect(shape.path(in: stage).boundingRect == stage)
    }
}
