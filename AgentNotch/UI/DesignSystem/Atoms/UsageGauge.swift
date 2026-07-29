import AgentNotchCore
import Defaults
import SwiftUI

/// A small always-on gauge showing usage.
///
/// Uses the glyph dictionary (`Glyph`) entries A' (RING) and E (NUMERIC 5×7) directly.
/// Intended for the left wing of the list's top bar, one per agent, side by side.
///
/// # Display style (`Defaults[.usageGaugeStyle]`, chosen in Settings)
/// - `.ring`: a 13×13 ring lit in angular order. Unlit cells carry a faint `agentType` color
///   so the hue says which agent's gauge it is
/// - `.number`: two 5×7 digits fitted into the 13×13 frame (numeric glyphs are all 5×7)
///
/// **Show one or the other, never both.** A % label next to the ring duplicates the same
/// information and produces "I picked the ring in Settings but the number shows too".
/// Agents are distinguished by hue instead. Where the ring is required regardless of the
/// setting (the usage page heading), pass `forcedStyle`.
///
/// When `usedPercent` is nil (before the first poll) it shows **a spinning arc**. Showing
/// nothing reads as "there is no gauge", and a 0% ring is misread as "zero usage", so it is
/// replaced by motion that cannot be read as a number. Under Reduce Motion the same arc is static.
///
/// Handling clicks is the caller's job (navigating to the usage detail page). This view is a
/// pure display component with no tap handling, so it also works as a Button label.
struct UsageGauge: View {
    /// Usage from 0 to 100. nil while not yet fetched (loading).
    let usedPercent: Double?
    /// Which agent's usage this is. Used for identification via the lit/unlit dot hue.
    /// nil for a neutral color.
    var agentType: AgentType?
    /// Size of one side of the whole grid.
    var size: CGFloat = 21
    /// Pins the display style, ignoring the setting. Use where **the number is already shown
    /// separately alongside and the shape (ring) is what's needed**, as in the usage page
    /// heading. nil follows the setting.
    var forcedStyle: UsageGaugeStyle?
    /// A fetch was attempted but there is no value (pay-as-you-go with no rate limit,
    /// no credentials, fetch failure, and so on).
    ///
    /// `usedPercent == nil` means "not fetched yet" — loading — so **the unavailable case is
    /// distinguished by this flag**. Setting it stops the spinner and shows an outline-only
    /// ring (a spinner that keeps going suggests a value will eventually arrive).
    var isUnavailable: Bool = false

    @Default(.usageGaugeStyle) private var settingStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: UsageGaugeStyle { forcedStyle ?? settingStyle }

    private var clampedPercent: Double { min(max(usedPercent ?? 0, 0), 100) }

    /// Color of the lit dots (the used portion, or the digits).
    ///
    /// The provider hue remains stable across every usage level, so a lone gauge keeps its
    /// identity even when the other provider is unavailable.
    private var valueColor: Color {
        agentType?.color ?? .secondary
    }

    /// Color of the unlit dots (the rest of the ring). A faint agent hue, used for identification.
    private var trackColor: Color {
        (agentType?.color ?? .secondary).opacity(0.3)
    }

    private var dot: CGFloat {
        let pitch = size / CGFloat(Glyph.stateSize)
        return max(1, pitch * 2 / 3)
    }

    private var gap: CGFloat {
        max(0, size / CGFloat(Glyph.stateSize) - dot)
    }

    /// Time for one full spinner revolution.
    private let spinDuration: TimeInterval = 1.1
    /// Time for the value to fill in once loading finishes.
    private let settleDuration: TimeInterval = 0.55

    /// The moment the value settled. Non-nil only while the transition plays.
    @State private var settleStart: Date?

    /// Whether it is loading. Excludes the case where a fetch found no value (`isUnavailable`).
    private var isLoading: Bool { usedPercent == nil && !isUnavailable }

    var body: some View {
        Group {
            if isLoading, !reduceMotion {
                // The animation is discrete — positions jump a dot at a time — so the phase is
                // driven by TimelineView rather than implicit animation (same as `StateGlyphView`).
                TimelineView(.animation(minimumInterval: spinDuration / 40)) { context in
                    GlyphView(bitmap: spinnerBitmap(at: context.date), dot: dot, gap: gap)
                }
            } else if let settleStart, !reduceMotion {
                TimelineView(.animation(minimumInterval: settleDuration / 40)) { context in
                    GlyphView(
                        bitmap: settleBitmap(at: context.date, from: settleStart),
                        dot: dot,
                        gap: gap
                    )
                }
            } else {
                GlyphView(bitmap: bitmap, dot: dot, gap: gap)
            }
        }
        .onChange(of: isLoading) { wasLoading, nowLoading in
            // Only animate the moment loading ends. Refilling from 0 on every later update
            // (the re-fetch every 3 minutes) would keep moving in the corner of the eye.
            // If it ended without a value (isUnavailable) there is nothing to fill, so skip it.
            guard wasLoading, !nowLoading, usedPercent != nil else { return }
            settleStart = Date()
        }
        .task(id: settleStart) {
            guard settleStart != nil else { return }
            // Once it finishes, collapse the TimelineView so per-frame re-evaluation stops.
            try? await Task.sleep(for: .seconds(settleDuration))
            settleStart = nil
        }
        .accessibilityElement()
        .accessibilityLabel(agentType.map { L("\($0.displayName) usage") } ?? L("Usage"))
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        if let usedPercent { return L("\(Int(min(max(usedPercent, 0), 100).rounded())) percent") }
        return isUnavailable ? L("Unavailable") : L("Loading")
    }

    /// The loading → settled transition.
    ///
    /// The spinning arc hands off directly into **a ring filling** from 12 o'clock to the target
    /// (ring style), or **a number running up** from 0 to the target (number style). Both
    /// overshoot slightly and come back, so the motion says "the value landed and stopped".
    private func settleBitmap(at date: Date, from start: Date) -> GlyphBitmap {
        let elapsed = date.timeIntervalSince(start)
        let progress = min(1, max(0, elapsed / settleDuration))
        let shown = clampedPercent * easeOutBack(progress)
        switch style {
        case .ring:
            return Glyph.ring(
                percent: min(100, max(0, shown)),
                lit: valueColor,
                track: trackColor
            )
        case .number:
            let value = min(99, max(0, Int(shown.rounded())))
            return Glyph.framedNumber(String(value), color: valueColor)
        }
    }

    /// 0→1, overshooting the end slightly before returning (for a click-into-place feel).
    private func easeOutBack(_ t: Double) -> Double {
        let overshoot = 1.2
        let p = t - 1
        return 1 + (overshoot + 1) * (p * p * p) + overshoot * (p * p)
    }

    private func spinnerBitmap(at date: Date) -> GlyphBitmap {
        let elapsed = date.timeIntervalSinceReferenceDate
        let phase = elapsed.truncatingRemainder(dividingBy: spinDuration) / spinDuration
        return Glyph.ringSpinner(
            phase: phase,
            lit: agentType?.color ?? .secondary,
            track: trackColor.opacity(0.4)
        )
    }

    private var bitmap: GlyphBitmap {
        guard usedPercent != nil else {
            if isUnavailable {
                // When nothing could be fetched, an outline-only ring. It neither moves nor
                // lights anything, so it reads as neither "0%" nor "loading" — the absence of
                // a value is visible as such.
                return Glyph.ring(percent: 0, lit: trackColor, track: trackColor)
            }
            // Loading display under Reduce Motion. The arc is frozen at a fixed phase so it
            // is not confused with a 0% ring.
            return Glyph.ringSpinner(
                phase: 0,
                lit: agentType?.color ?? .secondary,
                track: trackColor.opacity(0.4)
            )
        }
        switch style {
        case .ring:
            return Glyph.ring(percent: clampedPercent, lit: valueColor, track: trackColor)
        case .number:
            // Only two digits fit, so 100% is rounded down to 99.
            return Glyph.framedNumber(String(min(99, Int(clampedPercent.rounded()))), color: valueColor)
        }
    }

}

#Preview("Usage Gauge") {
    VStack(spacing: 20) {
        ForEach([12.0, 78.0, 95.0], id: \.self) { percent in
            HStack(spacing: 20) {
                UsageGauge(usedPercent: percent, agentType: .claudeCode, size: 32)
                UsageGauge(usedPercent: percent, agentType: .codex, size: 32)
                Text("\(Int(percent))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        UsageGauge(usedPercent: nil, agentType: .claudeCode, size: 32)
    }
    .padding(24)
    .background(Color.black)
}
