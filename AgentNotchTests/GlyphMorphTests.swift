import Foundation
import SwiftUI
import Testing

@testable import AgentNotch

/// Verifies that state-glyph morphing behaves as designed.
///
/// The visual result itself cannot be tested, but `GlyphMorph.frame` is a pure
/// function with a deterministic set of lit cells, so invariants such as matching the
/// endpoints, staying inside the grid, and converging on the empty figure can all be
/// pinned as regression tests.
@Suite("GlyphMorph Tests")
@MainActor
struct GlyphMorphTests {
    /// The set of lit cell positions (colors are ignored).
    private func litPositions(_ bitmap: GlyphBitmap) -> Set<Int> {
        Set(
            (0..<bitmap.rows).flatMap { row in
                (0..<bitmap.cols).compactMap { col in
                    bitmap.cell(row: row, col: col).on ? row * bitmap.cols + col : nil
                }
            }
        )
    }

    @Test("t=0 returns the old figure and t=1 the new one, unchanged")
    func endpointsAreExact() {
        let from = Glyph.state(.standby, phase: 0.5)
        let to = Glyph.state(.working, phase: 0)
        #expect(GlyphMorph.frame(from: from, to: to, t: 0) == from)
        #expect(GlyphMorph.frame(from: from, to: to, t: 1) == to)
        // Out-of-range values clamp to the endpoints.
        #expect(GlyphMorph.frame(from: from, to: to, t: -0.5) == from)
        #expect(GlyphMorph.frame(from: from, to: to, t: 1.5) == to)
    }

    @Test("Just before and after the endpoints the lit cells match them, so dots do not jump on landing")
    func nearEndpointsMatchPositions() {
        let from = Glyph.state(.standby, phase: 0.5)
        let to = Glyph.state(.working, phase: 0)
        // Right after the start: rounding keeps every dot at its old position.
        #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: 0.001)) == litPositions(from))
        // Just before landing: every dot has reached its new position, stagger included.
        #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: 0.999)) == litPositions(to))
    }

    @Test("A mid-transition frame differs from both endpoints, so the transition is visible")
    func midFrameDiffersFromEndpoints() {
        let from = Glyph.state(.standby, phase: 0.5)
        let to = Glyph.state(.working, phase: 0)
        let mid = GlyphMorph.frame(from: from, to: to, t: 0.5)
        #expect(mid != from)
        #expect(mid != to)
        // The dots never all disappear mid-transition.
        #expect(!litPositions(mid).isEmpty)
    }

    @Test("Morphing a figure into itself never moves a lit cell")
    func identityMorphKeepsPositions() {
        let bitmap = Glyph.state(.thinking, phase: 0.25)
        for t in [0.25, 0.5, 0.75] {
            #expect(litPositions(GlyphMorph.frame(from: bitmap, to: bitmap, t: t)) == litPositions(bitmap))
        }
    }

    @Test("Dots stay inside the grid in every intermediate frame")
    func dotsStayOnGrid() {
        let from = Glyph.state(.alert, phase: 0)
        let to = Glyph.state(.swarm(active: 9))
        for t in stride(from: 0.1, through: 0.9, by: 0.1) {
            let frame = GlyphMorph.frame(from: from, to: to, t: t)
            #expect(frame.rows == Glyph.stateSize)
            #expect(frame.cols == Glyph.stateSize)
            // The cells array matches its declared size, so nothing was written out of bounds.
            #expect(frame.cells.count == frame.rows)
            #expect(frame.cells.allSatisfy { $0.count == frame.cols })
        }
    }

    @Test("A transition to the empty figure fades dots out in place")
    func morphToEmptyFadesInPlace() {
        let from = Glyph.state(.standby, phase: 0.5)
        // complete at phase 0 is the empty figure; the check mark is drawn after the morph.
        let to = Glyph.state(.complete, phase: 0)
        #expect(litPositions(to).isEmpty)
        // With nowhere to move, the lit cells stay a subset of the old figure. Opacity
        // fades continuously to 0, so very faint dots can remain while t < 1.
        for t in [0.2, 0.5, 0.8, 0.999] {
            #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: t)).isSubset(of: litPositions(from)))
        }
        // The lit count decreases monotonically and is exactly zero at t=1.
        #expect(
            litPositions(GlyphMorph.frame(from: from, to: to, t: 0.9)).count
                < litPositions(GlyphMorph.frame(from: from, to: to, t: 0.1)).count
        )
        #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: 1)).isEmpty)
    }

    @Test("A transition from the empty figure fades dots in place")
    func morphFromEmptyFadesInPlace() {
        let from = Glyph.state(.complete, phase: 0)
        let to = Glyph.state(.working, phase: 0)
        for t in [0.2, 0.5, 0.8] {
            #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: t)).isSubset(of: litPositions(to)))
        }
        #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: 0.999)) == litPositions(to))
    }

    @Test("Between figures of different sizes, the intermediate lit count never exceeds the sum of both")
    func litCountStaysBounded() {
        let from = Glyph.state(.standby, phase: 0.25)  // a ring (many dots)
        let to = Glyph.state(.working, phase: 0)  // a small core
        let bound = litPositions(from).count + litPositions(to).count
        for t in stride(from: 0.1, through: 0.9, by: 0.1) {
            #expect(litPositions(GlyphMorph.frame(from: from, to: to, t: t)).count <= bound)
        }
    }
}
