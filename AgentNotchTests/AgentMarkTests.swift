import CoreGraphics
import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Verifies that the embedded official logo SVG paths parse into properly closed
/// shapes with our hand-rolled parser.
///
/// Whether a logo *looks* right can only be judged by eye, but **that the parse
/// did not break** is measurable: the bounding box stays within the expected
/// viewBox, it fits a given rect while preserving aspect ratio, and no command
/// was misread (i.e. the area is not wildly off).
@Suite("Agent Mark SVG Tests")
@MainActor
struct AgentMarkTests {
    @Test("Claude path fits within the 125-unit viewBox")
    func claudePathFitsViewBox() {
        let path = SVGPathParser.path(from: AgentMarkPath.claude)
        #expect(!path.isEmpty)
        let box = path.boundingRect
        // The source SVG spans 0...125 (viewBox 0 0 125 125).
        #expect(box.minX >= -0.01)
        #expect(box.minY >= -0.01)
        #expect(box.maxX <= 125.01)
        #expect(box.maxY <= 125.01)
        // A near-square symbol. If it is badly squashed, a command was misread.
        #expect(abs(box.width - box.height) < 2)
    }

    @Test("OpenAI Blossom body sits in the center of the viewBox")
    func openAIPathIsCentered() {
        let path = SVGPathParser.path(from: AgentMarkPath.openAI)
        #expect(!path.isEmpty)
        let box = path.boundingRect
        // The viewBox is 716 units, but the logo body occupies 183...533.
        #expect(box.minX > 180)
        #expect(box.maxX < 536)
        #expect(abs(box.width - box.height) < 2)
    }

    /// `AgentMarkShape` normalizes by the **actual drawn bounds**, not the viewBox,
    /// so a logo with viewBox padding (like OpenAI's) still renders at the same
    /// visual size as the others.
    @Test("Fits the given rect while preserving aspect ratio")
    func shapeFitsGivenRect() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        for commands in [AgentMarkPath.claude, AgentMarkPath.openAI] {
            let box = AgentMarkShape(commands: commands).path(in: rect).boundingRect
            #expect(box.width <= 20.01)
            #expect(box.height <= 20.01)
            // Uses the full short edge instead of shrinking by the padding.
            #expect(max(box.width, box.height) > 19.5)
            // Centered in the rect.
            #expect(abs(box.midX - rect.midX) < 0.01)
            #expect(abs(box.midY - rect.midY) < 0.01)
        }
    }

    /// Regression test guarding against dropped parser commands. Builds expressions
    /// with relative coordinates, repeated arguments, and a minus sign acting as a
    /// separator.
    @Test("Handles M/L/H/V/C/Z, relative coordinates, and minus-sign separators")
    func parsesSupportedCommands() {
        // A square walking 10,10 -> 20,10 -> 20,20 -> 10,20 and closing,
        // written with a mix of absolute, relative, and H/V commands.
        let square = SVGPathParser.path(from: "M10 10H20V20h-10Z")
        #expect(square.boundingRect == CGRect(x: 10, y: 10, width: 10, height: 10))

        // Minus sign as a separator (`L10-5` = 10, -5).
        let negative = SVGPathParser.path(from: "M0 0L10-5Z")
        #expect(negative.boundingRect == CGRect(x: 0, y: -5, width: 10, height: 5))

        // Repeated arguments (two pairs for a single `L`).
        let polyline = SVGPathParser.path(from: "M0 0L5 5 10 0Z")
        #expect(polyline.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 5))

        // An unsupported command (arc A) must not crash the parser.
        let withArc = SVGPathParser.path(from: "M0 0L10 0A5 5 0 0 1 0 0Z")
        #expect(!withArc.isEmpty)
    }

    // MARK: - Parse caching

    /// SwiftUI calls `path(in:)` on every hit test, not only on every draw, so an uncached parse
    /// re-scanned kilobytes of commands on each click and pointer move — enough to visibly stall
    /// the compact→expanded transition. These pin the cache's two obligations: it must be fast on
    /// repeat, and it must not hand one mark's geometry to another.
    @Test("Repeating a mark's path is far cheaper than the first parse")
    func cachesParsedPaths() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        // A path string no other test uses, so the first call is genuinely cold. Measuring a
        // vendor mark here would depend on whether another test had already warmed the cache,
        // and the suite runs in parallel.
        let commands = "M0 0" + String(repeating: "L1 1L2 0", count: 400) + "Z"
        let shape = AgentMarkShape(commands: commands)

        let coldStart = DispatchTime.now()
        _ = shape.path(in: rect)
        let cold = DispatchTime.now().uptimeNanoseconds - coldStart.uptimeNanoseconds

        let iterations = 500
        let warmStart = DispatchTime.now()
        for _ in 0..<iterations { _ = shape.path(in: rect) }
        let warm =
            (DispatchTime.now().uptimeNanoseconds - warmStart.uptimeNanoseconds) / UInt64(iterations)

        // A generous margin: the point is the order of magnitude, not a specific timing. Without
        // the cache a repeat costs the same as the first parse, so anything near parity is the
        // regression this guards against.
        #expect(
            warm * 5 < cold,
            "a repeated path(in:) cost \(warm)ns against a first parse of \(cold)ns"
        )
    }

    @Test("Each mark keeps its own geometry through the cache")
    func cacheKeepsMarksDistinct() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        let claude = AgentMarkShape(commands: AgentMarkPath.claude).path(in: rect)
        let openAI = AgentMarkShape(commands: AgentMarkPath.openAI).path(in: rect)

        #expect(!claude.isEmpty)
        #expect(!openAI.isEmpty)
        // Both are normalized into the same rect, so equal bounds are expected; the paths
        // themselves must still differ, which is what a mixed-up cache entry would break.
        #expect(claude.description != openAI.description)

        // Re-reading after the other mark was cached must still return the original geometry.
        let claudeAgain = AgentMarkShape(commands: AgentMarkPath.claude).path(in: rect)
        #expect(claudeAgain.description == claude.description)
    }

    /// The cache must not become a size cache: the same mark is drawn at several sizes (the text
    /// size setting scales it), and every one has to be normalized to the rect it was asked for.
    @Test("A cached mark still fits whatever rect it is given")
    func cachedMarkRespectsRequestedRect() {
        let commands = AgentMarkPath.claude
        for side in [8.0, 10.0, 26.0, 64.0] as [CGFloat] {
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            let box = AgentMarkShape(commands: commands).path(in: rect).boundingRect

            #expect(max(box.width, box.height) <= side + 0.01)
            #expect(max(box.width, box.height) > side - 0.5)
            #expect(abs(box.midX - rect.midX) < 0.01)
            #expect(abs(box.midY - rect.midY) < 0.01)
        }
    }
}
