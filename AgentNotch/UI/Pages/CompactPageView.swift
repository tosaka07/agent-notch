import AgentNotchCore
import SwiftUI

/// UI for the `compact` / `notification` modes.
///
/// # Where the information lives
/// - Left wing: `StateGlyphView` — the top-priority session's state as a 13×13
///   dot glyph.
/// - Center: nothing, because it is **hidden on displays with a physical
///   notch**. A tool-name ticker appears only without a notch, in floating-bar
///   presentation.
/// - Right wing: `PixelCounter` — running / total.
///
/// # Design principles
/// - The wings hold glyphs only; no text.
/// - State stays readable from shape alone if color is gone, because the glyph
///   figures differ.
struct CompactPageView: View {
    let viewModel: NotchViewModel
    let notificationManager: NotchNotificationManager
    let focusController: NotificationFocusController
    @ObservedObject var sessionManager: SessionManager
    let motion: NotchOverviewMotion

    var body: some View {
        let sessions = sessionManager.activeSessions
        let primary = Self.primarySession(sessions)
        let wing = viewModel.sideWidth
        let notchHeight = viewModel.physicalNotchHeight
        // The wings extend past the notch's rounded corners, so using them as-is
        // would spread the canvas beyond the notch's clip region. An edgeMargin
        // at both ends keeps the effective drawing area inside what the notch
        // makes visible.
        let edgeMargin: CGFloat = 8
        let wingInner = max(0, wing - edgeMargin)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: edgeMargin)

                // Left wing: state glyph
                ZStack {
                    if let primary {
                        StateGlyphView(
                            state: leftWingState(primary),
                            size: min(wingInner, notchHeight - 12),
                            animationStartTime: primary.doneAt,
                            isAnimationActive: motion.runsCompactAnimation
                        )
                    }
                }
                .frame(width: wingInner, height: notchHeight)
                .offset(x: motion.leadingWingOffset)
                .opacity(motion.compactOpacity)

                // Center: the region overlapping the physical notch. Nothing is
                // drawn here on displays that have one, since it is invisible.
                ZStack {
                    if !viewModel.hasPhysicalNotch, motion.runsCompactAnimation {
                        // `status` flips constantly on tool events, so decide from
                        // whether subagents are running instead.
                        if let primary, primary.runningSubagentCount > 0 {
                            TimelineView(.periodic(from: .now, by: 2.5)) { context in
                                if let text = subagentTickerText(primary, at: context.date) {
                                    TickerText(
                                        text: text,
                                        font: DSTypography.mono(10, weight: .medium),
                                        color: DSColors.inkDim
                                    )
                                }
                            }
                        } else if let toolName = activeToolName(sessions) {
                            TickerText(
                                text: toolName,
                                font: DSTypography.mono(10, weight: .medium),
                                color: DSColors.inkDim
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: notchHeight)
                .clipped()
                .opacity(motion.compactOpacity)

                // Right wing: PixelCounter. The value is always ink so it stays
                // legible; the total is inkDim to separate the two.
                ZStack {
                    if !sessions.isEmpty {
                        let running = sessions.filter(\.status.isRunning).count
                        PixelCounter(
                            value: running,
                            total: sessions.count,
                            valueColor: DSColors.ink,
                            totalColor: DSColors.ink.opacity(0.55)
                        )
                    }
                }
                .frame(width: wingInner, height: notchHeight)
                .offset(x: motion.trailingWingOffset)
                .opacity(motion.compactOpacity)

                Color.clear.frame(width: edgeMargin)
            }

            // Notification rows (only in .notification mode)
            if viewModel.mode == .notification {
                VStack(spacing: 0) {
                    ForEach(Array(notificationManager.items.enumerated()), id: \.element.id) { index, item in
                        NotificationRowButton(
                            content: item.content,
                            isFocused: focusController.isFocused && index == focusController.focusIndex
                        ) {
                            item.onTap?()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        // Expanded mode is wider than compact. Keeping this lightweight page at
        // its own stable width prevents the wings from being re-laid out across
        // the session list before their outward motion begins.
        .frame(width: viewModel.compactPresentationWidth)
    }

    // MARK: - Selection helpers

    /// The top-priority session: urgency ascending, then lastActivityAt descending.
    static func primarySession(_ sessions: [UnifiedSession]) -> UnifiedSession? {
        sessions.min { lhs, rhs in
            if lhs.status.urgencyRank != rhs.status.urgencyRank {
                return lhs.status.urgencyRank < rhs.status.urgencyRank
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    /// The state glyph shown in the left wing.
    ///
    /// When a session with running subagents finishes, `dotPattern` immediately
    /// returns `.complete` (a checkmark) — but that is the exact moment the
    /// completion banner appears, so the swarm display (parallel subagents)
    /// shown a heartbeat earlier looks like it was abruptly swapped for a
    /// checkmark. The swarm display is therefore held while the completion
    /// notification is up, reverting to the normal completed state once the
    /// notification goes away.
    private func leftWingState(_ primary: UnifiedSession) -> Glyph.State {
        // The completion banner switches the mode to `.notification` as it
        // enqueues (NotchEventRouter.handleSessionCompleted/handleSessionSwept),
        // so guarding on mode first keeps compact's body re-evaluation out of
        // changes to notificationManager.items.
        guard viewModel.mode == .notification,
            primary.status == .done,
            primary.subagentCountAtCompletion > 0,
            notificationManager.items.contains(where: { $0.id == primary.id })
        else {
            return primary.glyphState
        }
        return .swarm(active: primary.subagentCountAtCompletion)
    }

    private func activeToolName(_ sessions: [UnifiedSession]) -> String? {
        sessions.lazy
            .compactMap { $0.currentTool }
            .first { $0.status == .running }
            .map(\.name)
    }

    /// Aggregates the agentTypes of running subagents into `×N TYPE` text. With
    /// more than one type it cycles, driven by the date from the caller's
    /// `TimelineView(.periodic(by: 2.5))`.
    private func subagentTickerText(_ session: UnifiedSession, at date: Date) -> String? {
        let running = session.subagents.filter { $0.status == .running }
        guard !running.isEmpty else { return nil }
        let counts = Dictionary(grouping: running, by: \.agentType).mapValues(\.count)
        let types = counts.keys.sorted()
        guard !types.isEmpty else { return nil }
        let index = Int(date.timeIntervalSinceReferenceDate / 2.5) % types.count
        let type = types[index]
        return "×\(counts[type] ?? 0) \(type.uppercased())"
    }
}
