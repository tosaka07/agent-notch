import SwiftUI

/// A view that animates the empty-state glyph (sleeping face + zzz).
///
/// The zzz cycle takes 2.4 seconds — the same interval as `standby`'s breathing. One is added
/// per beat, and on the fourth beat they clear for a breath. Like `StateGlyphView`, it uses
/// **`TimelineView` to switch only which cells are lit** (coordinates never move by fractions).
struct DozingGlyphView: View {
    /// Rendered height of the vertical axis (13 cells). Width follows from the cell-count ratio.
    var height: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 2.4

    private var dot: CGFloat {
        let pitch = height / CGFloat(Glyph.stateSize)
        return max(1, pitch * 2 / 3)
    }

    private var gap: CGFloat {
        let pitch = height / CGFloat(Glyph.stateSize)
        return max(0, pitch - dot)
    }

    var body: some View {
        if reduceMotion {
            // No motion; freeze at the most informative phase (all three zzz).
            GlyphView(bitmap: Glyph.dozing(phase: 0.9), dot: dot, gap: gap)
        } else {
            // Only the 0.6s-per-beat transitions need to read, so per-frame evaluation is overkill.
            TimelineView(.animation(minimumInterval: 0.1)) { context in
                GlyphView(bitmap: Glyph.dozing(phase: phase(at: context.date)), dot: dot, gap: gap)
            }
        }
    }

    private func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        return elapsed.truncatingRemainder(dividingBy: Self.period) / Self.period
    }
}

#Preview("F · DOZING") {
    VStack(spacing: 20) {
        DozingGlyphView(height: 26)
        DozingGlyphView(height: 40)
    }
    .padding(32)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
