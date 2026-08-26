import SwiftUI

/// A view that animates a state glyph (13×13).
///
/// # Animation spec
/// | State | Period | Motion |
/// | --- | --- | --- |
/// | STANDBY | 2400ms | Only the ring radius breathes ±1 cell (no dots added or removed) |
/// | THINKING | 1600ms | A sine wave advances one full phase (rows round to whole cells) |
/// | WORKING | 900ms | The core pulses between radius 2 and 4 |
/// | SWARM(n) | 120ms/slot | Slots fill in launch order (static; motion comes from the count) |
/// | ALERT | 1000ms | Blinks on a 55/45 duty; the off phase stays at 0.22 |
/// | QUESTION | 1000ms | Blinks on the same duty as ALERT, with a distinct figure and color |
/// | COMPLETE | 480ms | Draws the check in from the lower left, then holds |
///
/// # Re-evaluation frequency
/// Only standby / thinking / working / complete — where radius or phase changes continuously —
/// need per-frame evaluation. The blinking states (alert / planReview / fault) and the static
/// swarm get by on a coarse tick, hence the split via
/// `TimelineView(.animation(minimumInterval:))`.
///
/// # Morphing between states
/// The frame actually on screen at the moment the state changes is frozen, then morphed via
/// `GlyphMorph` into the new state's phase-0 figure (old dots travel across the grid and
/// rearrange into the new figure). The morph's completion time becomes the phase origin, so the
/// new state's animation always starts at phase 0 and joins the morph's landing seamlessly.
/// If the state changes again mid-morph, that instant's composed frame is frozen as the next
/// `from`, so dots never jump even through back-to-back transitions.
struct StateGlyphView: View {
    let state: Glyph.State
    /// One side of the whole grid. Derived from 13 cells (dot 2 + gap 1 → pitch 3).
    var size: CGFloat = 26
    /// When the complete check starts drawing. nil uses absolute time.
    var animationStartTime: Date?
    /// A hidden retained owner can pause per-frame TimelineView updates without
    /// discarding this view's identity or morph state.
    var isAnimationActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The morph in progress. nil means normal drawing.
    @State private var morph: Morph?
    /// The phase origin for a transition this view itself witnessed (= the morph's completion
    /// time). Takes priority over `animationStartTime`. When the view is rebuilt it resets to
    /// nil and falls back to `animationStartTime`, so the complete check is not redrawn every
    /// time it reappears.
    @State private var phaseAnchor: Date?

    private struct Morph: Equatable {
        /// The frozen frame from the moment the transition began. The morph runs from here to
        /// the new state's phase 0.
        let from: GlyphBitmap
        let startedAt: Date
    }

    /// Dot diameter that fits 13 cells into `size` (2/3 of the pitch is dot, 1/3 is gap).
    private var dot: CGFloat {
        let pitch = size / CGFloat(Glyph.stateSize)
        return max(1, pitch * 2 / 3)
    }

    private var gap: CGFloat {
        let pitch = size / CGFloat(Glyph.stateSize)
        return max(0, pitch - dot)
    }

    /// Only patterns whose shape changes continuously are evaluated per frame.
    private var minimumTickInterval: TimeInterval? {
        switch state {
        case .standby, .thinking, .working, .complete: nil
        // Blinking and static patterns are fine at 0.1s steps — only the duty transitions
        // need to read.
        case .alert, .question, .planReview, .fault, .swarm: 0.1
        }
    }

    var body: some View {
        content
            .onChange(of: state) { oldState, _ in
                beginMorph(from: oldState)
            }
            // Once the morph ends, reset to nil and go back to the coarse blink tick.
            // Being a `task(id:)`, it cancels automatically when the morph is replaced or the
            // view goes away.
            .task(id: morph?.startedAt) {
                guard morph != nil else { return }
                try? await Task.sleep(for: .seconds(GlyphMorph.duration + 0.05))
                if !Task.isCancelled { morph = nil }
            }
    }

    @ViewBuilder
    private var content: some View {
        if reduceMotion || !isAnimationActive {
            // When motion is disabled, freeze at the most informative phase.
            GlyphView(bitmap: Glyph.state(state, phase: state == .complete ? 1 : 0.5), dot: dot, gap: gap)
        } else if let interval = minimumTickInterval, morph == nil {
            TimelineView(.animation(minimumInterval: interval)) { context in
                GlyphView(bitmap: bitmap(at: context.date), dot: dot, gap: gap)
            }
        } else {
            // During a morph even the blinking states evaluate per frame, since dots keep moving.
            TimelineView(.animation) { context in
                GlyphView(bitmap: bitmap(at: context.date), dot: dot, gap: gap)
            }
        }
    }

    /// Begins a state transition: freezes the frame actually on screen at that instant as
    /// `from`, and moves the phase origin to the morph's completion time.
    private func beginMorph(from oldState: Glyph.State) {
        guard !reduceMotion else { return }
        let now = Date()
        let frozen = bitmap(at: now, state: oldState)
        morph = Morph(from: frozen, startedAt: now)
        phaseAnchor = now.addingTimeInterval(GlyphMorph.duration)
    }

    private func bitmap(at date: Date) -> GlyphBitmap {
        bitmap(at: date, state: state)
    }

    /// During a morph, runs from the frozen frame to `state`'s phase-0 figure; afterwards,
    /// normal drawing. `state` is a parameter so the old state's frame can be frozen when a
    /// transition starts.
    private func bitmap(at date: Date, state: Glyph.State) -> GlyphBitmap {
        if let morph {
            let t = date.timeIntervalSince(morph.startedAt) / GlyphMorph.duration
            if t < 1 {
                return GlyphMorph.frame(from: morph.from, to: Glyph.state(state, phase: 0), t: t)
            }
        }
        return Glyph.state(state, phase: phase(at: date, state: state))
    }

    /// Phase from 0 to 1. Non-looping patterns (complete) stop at 1.
    private func phase(at date: Date, state: Glyph.State) -> Double {
        let elapsed: TimeInterval
        if let phaseAnchor {
            elapsed = max(0, date.timeIntervalSince(phaseAnchor))
        } else if let animationStartTime {
            elapsed = max(0, date.timeIntervalSince(animationStartTime))
        } else {
            elapsed = date.timeIntervalSinceReferenceDate
        }
        let duration = state.duration
        guard duration > 0 else { return 0 }
        guard state.loops else { return min(1, elapsed / duration) }
        return (elapsed.truncatingRemainder(dividingBy: duration)) / duration
    }
}

#Preview("A · STATE") {
    let states: [(String, Glyph.State)] = [
        ("STANDBY", .standby), ("THINKING", .thinking), ("WORKING", .working),
        ("SWARM(5)", .swarm(active: 5)), ("ALERT", .alert), ("QUESTION", .question),
        ("PLAN REVIEW", .planReview),
        ("COMPLETE", .complete), ("FAULT", .fault),
    ]
    return LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), spacing: 18
    ) {
        ForEach(states, id: \.0) { item in
            HStack(spacing: 12) {
                StateGlyphView(state: item.1, size: 26)
                Text(item.0)
                    .font(DSTypography.mono(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DSColors.inkDim)
            }
        }
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}

/// Cycles states at a fixed interval to eyeball the transition morph (dot travel and color blend).
#Preview("A · STATE MORPH") {
    let cycle: [Glyph.State] = [
        .standby, .thinking, .working, .swarm(active: 5), .alert, .question, .planReview, .fault,
        .complete,
    ]
    return TimelineView(.periodic(from: .now, by: 1.6)) { context in
        let index = Int(context.date.timeIntervalSinceReferenceDate / 1.6) % cycle.count
        HStack(spacing: 16) {
            StateGlyphView(state: cycle[index], size: 52)
            Text(String(describing: cycle[index]).uppercased())
                .font(DSTypography.mono(9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DSColors.inkDim)
                .frame(width: 120, alignment: .leading)
        }
        .padding(32)
    }
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
