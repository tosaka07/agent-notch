import Foundation
import Testing

@testable import AgentNotch

@Suite("Notch shell")
struct NotchShellTests {
    @Test("Expanded panel keeps a nonzero input surface")
    func expandedSurfaceIsNotFullyTransparent() {
        #expect(PanelScrimPolicy.opacity(showsSurface: true) > 0)
        #expect(PanelScrimPolicy.opacity(showsSurface: false) == 1)
    }

    @Test("Compact hover follows the target panel bounds, not the fixed stage")
    func compactHoverIsScopedToPanel() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/Root/NotchShell.swift"),
            encoding: .utf8
        )
        let fixedStageStart = try #require(
            source.range(of: "    private func fixedStageContent(_ content: Content)")
        )
        let nextSection = try #require(
            source.range(
                of: "    /// Completion glow remains",
                range: fixedStageStart.upperBound..<source.endIndex
            )
        )
        let fixedStage = source[fixedStageStart.lowerBound..<nextSection.lowerBound]

        #expect(fixedStage.contains(".onHover"))
        #expect(fixedStage.contains("withAnimation"))
        #expect(source.components(separatedBy: ".onHover").count - 1 == 1)
    }
}
