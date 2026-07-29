import SwiftUI

/// A pure function that morphs between two `GlyphBitmap`s dot by dot.
///
/// Instead of a state glyph swapping abruptly, the old figure's dots **travel across the grid**
/// and rearrange into the new figure's dots.
///
/// # Staying within the constraint
/// `GlyphBitmap`'s absolute constraint — dots never move sub-pixel — is upheld by rounding the
/// interpolated coordinates to whole cells. Dots do not glide smoothly; they hop one cell at a
/// time, which actually suits the discreteness of a dot matrix.
///
/// # Correspondence
/// Lit dots in the old and new figures are greedily matched nearest-first. Where the counts
/// do not line up:
/// - Leftover old dots — move toward their nearest new dot as they fade out (absorption)
/// - Missing new dots — appear at their nearest old dot's position and move (splitting)
/// so it keeps the sense of "moving and rearranging" rather than a plain crossfade.
/// Colors in flight mix old → new through perceptual interpolation.
///
/// # Cost
/// Matching is O(n·m·log(n·m)) where n and m are lit-dot counts (at most ~40 for state glyphs).
/// Recomputing per frame is microseconds, so there is no cache: it stays **a pure function of
/// from / to / t**, favoring testability.
enum GlyphMorph {
    /// Total morph length in seconds, including the stagger.
    static let duration: TimeInterval = 0.28

    /// Fraction of the total time used to offset when dots start moving.
    /// The first dot starts at t=0 and the last at t=staggerRatio; all arrive at t=1.
    private static let staggerRatio = 0.25

    /// Composes one frame of the transition. `t` is 0–1 (outside the range the endpoints are
    /// returned as-is).
    static func frame(from: GlyphBitmap, to: GlyphBitmap, t: Double) -> GlyphBitmap {
        if t <= 0 { return from }
        if t >= 1 { return to }

        let rows = max(from.rows, to.rows)
        let cols = max(from.cols, to.cols)
        let tracks = makeTracks(from: litDots(of: from), to: litDots(of: to))

        var cells = Array(repeating: Array(repeating: DotCell.off, count: cols), count: rows)
        // Draw vanishing, then spawning, then moving dots, so that when two land on the same
        // cell the opaque one (move) wins.
        for kind in [Track.Kind.vanish, .spawn, .move] {
            for (index, track) in tracks.enumerated() where track.kind == kind {
                let progress = eased(t, index: index, count: tracks.count)
                guard let dot = evaluate(track, progress: progress) else { continue }
                cells[dot.y][dot.x] = .on(color: dot.color)
            }
        }
        return GlyphBitmap(rows: rows, cols: cols, cells: cells)
    }

    // MARK: - Internal representation

    private struct Dot {
        let x: Int
        let y: Int
        let color: Color
    }

    /// The travel plan for one dot. Its array position is the index used to order the stagger.
    private struct Track {
        enum Kind: Int {
            case move, vanish, spawn
        }

        let kind: Kind
        let fromX: Int, fromY: Int
        let toX: Int, toY: Int
        let fromColor: Color
        let toColor: Color
    }

    private static func litDots(of bitmap: GlyphBitmap) -> [Dot] {
        var dots: [Dot] = []
        for y in 0..<bitmap.rows {
            for x in 0..<bitmap.cols {
                let cell = bitmap.cell(row: y, col: x)
                guard cell.on else { continue }
                // Lit cells with no color fall back to the same default the renderer
                // (GlyphView) uses.
                dots.append(Dot(x: x, y: y, color: cell.color ?? DSColors.ink))
            }
        }
        return dots
    }

    private static func makeTracks(from fromDots: [Dot], to toDots: [Dot]) -> [Track] {
        // Sort all pairs by distance and match greedily nearest-first. Tie-breaking on index
        // keeps the result deterministic (Swift's sort is not stable).
        var pairs: [(f: Int, t: Int, d: Int)] = []
        pairs.reserveCapacity(fromDots.count * toDots.count)
        for (fi, from) in fromDots.enumerated() {
            for (ti, to) in toDots.enumerated() {
                let dx = from.x - to.x
                let dy = from.y - to.y
                pairs.append((fi, ti, dx * dx + dy * dy))
            }
        }
        pairs.sort { ($0.d, $0.f, $0.t) < ($1.d, $1.f, $1.t) }

        var fromMatched = Array(repeating: false, count: fromDots.count)
        var toMatched = Array(repeating: false, count: toDots.count)
        var tracks: [Track] = []
        for pair in pairs where !fromMatched[pair.f] && !toMatched[pair.t] {
            fromMatched[pair.f] = true
            toMatched[pair.t] = true
            let from = fromDots[pair.f]
            let to = toDots[pair.t]
            tracks.append(
                Track(
                    kind: .move, fromX: from.x, fromY: from.y, toX: to.x, toY: to.y,
                    fromColor: from.color, toColor: to.color
                )
            )
        }
        // Leftover old dots are drawn into their nearest new dot as they disappear
        // (if the new figure is empty, they fade out in place).
        for (fi, from) in fromDots.enumerated() where !fromMatched[fi] {
            let target = nearest(to: from, in: toDots) ?? from
            tracks.append(
                Track(
                    kind: .vanish, fromX: from.x, fromY: from.y, toX: target.x, toY: target.y,
                    fromColor: from.color, toColor: from.color
                )
            )
        }
        // Missing new dots split off from their nearest old dot
        // (if the old figure is empty, they fade in in place).
        for (ti, to) in toDots.enumerated() where !toMatched[ti] {
            let origin = nearest(to: to, in: fromDots) ?? to
            tracks.append(
                Track(
                    kind: .spawn, fromX: origin.x, fromY: origin.y, toX: to.x, toY: to.y,
                    fromColor: to.color, toColor: to.color
                )
            )
        }
        // Fix the stagger order to reading order (top→bottom, left→right).
        tracks.sort {
            ($0.fromY, $0.fromX, $0.toY, $0.toX, $0.kind.rawValue)
                < ($1.fromY, $1.fromX, $1.toY, $1.toX, $1.kind.rawValue)
        }
        return tracks
    }

    private static func nearest(to dot: Dot, in candidates: [Dot]) -> Dot? {
        candidates.min { lhs, rhs in
            distanceSquared(lhs, dot) < distanceSquared(rhs, dot)
        }
    }

    private static func distanceSquared(_ a: Dot, _ b: Dot) -> Int {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    // MARK: - Evaluation

    /// Evaluates a track at `progress` (0–1, already eased).
    /// A spawn at progress 0 and a vanish at progress 1 are invisible dots, so they are not
    /// drawn and yield their cell to another track.
    private static func evaluate(
        _ track: Track,
        progress: Double
    ) -> (x: Int, y: Int, color: Color)? {
        let x = lerp(track.fromX, track.toX, progress)
        let y = lerp(track.fromY, track.toY, progress)
        switch track.kind {
        case .move:
            return (x, y, track.fromColor.mix(with: track.toColor, by: progress))
        case .vanish:
            guard progress < 1 else { return nil }
            return (x, y, track.fromColor.opacity(1 - progress))
        case .spawn:
            guard progress > 0 else { return nil }
            return (x, y, track.toColor.opacity(progress))
        }
    }

    /// Interpolation between whole cells. Rounding **always keeps the dot on the grid**
    /// (no sub-pixel movement).
    private static func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int {
        Int((Double(a) + (Double(b) - Double(a)) * t).rounded())
    }

    /// easeInOut with a stagger: the track's position in the array offsets when it starts.
    private static func eased(_ t: Double, index: Int, count: Int) -> Double {
        let delay = count > 1 ? staggerRatio * Double(index) / Double(count - 1) : 0
        let local = min(1, max(0, (t - delay) / (1 - staggerRatio)))
        return local < 0.5 ? 4 * local * local * local : 1 - pow(-2 * local + 2, 3) / 2
    }
}
