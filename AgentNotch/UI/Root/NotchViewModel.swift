import AgentNotchCore
import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact {
        didSet {
            if mode != oldValue {
                Log.panel.info("Mode: \(oldValue) → \(mode)")
            }
        }
    }
    var isHovering: Bool = false {
        didSet {
            if isHovering != oldValue {
                Log.panel.debug("Hovering: \(isHovering)")
            }
        }
    }

    var physicalNotchWidth: CGFloat
    var physicalNotchHeight: CGFloat
    var hasActivity: Bool = false
    /// Whether this display has a physical notch.
    ///
    /// On a display with one, the center of the panel (the notch's own width) is
    /// **physically hidden**. Drawing there is wasted, so compact's center ticker
    /// only appears without a notch, i.e. in floating-bar presentation.
    var hasPhysicalNotch: Bool

    init(
        notchSize: CGSize = CGSize(width: 224, height: 38),
        initialMode: NotchMode = .compact,
        hasPhysicalNotch: Bool = true
    ) {
        self.physicalNotchWidth = notchSize.width
        self.physicalNotchHeight = notchSize.height
        self.mode = initialMode
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    private let notchCornerMargin: CGFloat = 6

    var sideWidth: CGFloat {
        max(0, physicalNotchHeight - 12) + 10
    }

    private var compactWidth: CGFloat {
        physicalNotchWidth + notchCornerMargin + (2 * sideWidth)
    }

    /// Stable width used by compact chrome even while the expanded page exists.
    ///
    /// This is intentionally independent from `mode`; otherwise the retained
    /// left and right wings would jump to 520pt before their transition starts.
    var compactPresentationWidth: CGFloat {
        isHovering ? compactWidth + 16 : compactWidth
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact:
            return compactPresentationWidth
        case .notification:
            return compactWidth
        case .expanded: return NotchPresentationLayout.expandedSize.width
        case .sessionDetail: return 620
        // On the usage page each window row has five columns — label, ticks,
        // percentage, remaining, absolute time — and the ticks are glyphs with a
        // fixed width that never shrink. At the list's 520 the right edge gets
        // cut off at the "large" text size, so it matches the detail page's 620,
        // which always fits the fixed columns plus the ticks.
        case .usage: return 620
        }
    }

    var notificationCount: Int = 0

    /// Measured height plus gap of the accessory hanging below the panel (the
    /// completion pill). Added to HotZoneTracker's outside-click region; 0 when
    /// hidden.
    var bottomAccessoryHeight: CGFloat = 0

    private let notificationItemHeight: CGFloat = 42

    var notchHeight: CGFloat {
        switch mode {
        case .compact:
            return isHovering ? physicalNotchHeight + 6 : physicalNotchHeight
        case .notification:
            let count = max(notificationCount, 1)
            return physicalNotchHeight + notificationItemHeight * CGFloat(count) + 6
        case .expanded:
            return NotchPresentationLayout.expandedSize.height
        case .sessionDetail:
            return 500
        case .usage:
            return 440
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact, .notification: 6
        case .expanded, .sessionDetail, .usage: 12
        }
    }

    /// Bottom corner radius of the physical notch itself.
    ///
    /// The compact panel is exactly the notch's size, so this equals its
    /// `bottomCornerRadius`. Even while the panel is extended, the black
    /// rectangle overlapping the notch must keep this radius — following the
    /// panel's radius instead would round it more than the notch and break the
    /// silhouette.
    var physicalNotchCornerRadius: CGFloat { 14 }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: physicalNotchCornerRadius
        case .notification: 16
        case .expanded, .sessionDetail, .usage: 24
        }
    }

    func toggle() {
        switch mode {
        case .compact, .notification: mode = .expanded
        case .expanded: mode = .compact
        // Detail pages go back to the list — toggle behaves as "one step back".
        case .sessionDetail, .usage: mode = .expanded
        }
    }

    func close() { mode = .compact }
    func showSession(_ id: String) { mode = .sessionDetail(sessionId: id) }
    /// Presents the first interruption, but never lets a later arrival replace the card the user
    /// is already answering. Resolution navigation advances the global FIFO explicitly.
    func showIncomingInterruption(_ id: String, sessionManager: SessionManager) {
        if case .sessionDetail(let visibleId) = mode,
            sessionManager.session(for: visibleId)?.currentInterruption != nil
        {
            return
        }
        showSession(sessionManager.nextPendingInterruptionSession()?.id ?? id)
    }
    func showUsage() { mode = .usage }
    func backToList() { mode = .expanded }
}
