import CoreGraphics
import SwiftUI

/// The two stable endpoints owned by the overview identity host.
///
/// Detail and usage pages deliberately return no target: they keep the
/// immediate page replacement that avoids retaining a heavy outgoing page.
enum NotchOverviewTarget: Equatable, Hashable, Sendable {
    case compact
    case expanded

    init?(mode: NotchMode) {
        switch mode {
        case .compact, .notification:
            self = .compact
        case .expanded:
            self = .expanded
        case .sessionDetail, .usage:
            return nil
        }
    }

    var expansion: CGFloat {
        switch self {
        case .compact: 0
        case .expanded: 1
        }
    }
}

/// Presentation values derived from one expansion progress.
///
/// One scalar is the module's interface so the left wing, right wing, and
/// expanded list cannot drift onto separate animation timelines. The values
/// are clamped because an interrupted spring may sample beyond an endpoint.
struct NotchOverviewMotion: Equatable, Sendable {
    private static let wingTravel: CGFloat = 18
    private static let listArrivalDistance: CGFloat = 8

    let expansion: CGFloat

    init(expansion: CGFloat) {
        self.expansion = min(max(expansion, 0), 1)
    }

    var leadingWingOffset: CGFloat {
        -Self.wingTravel * expansion
    }

    var trailingWingOffset: CGFloat {
        Self.wingTravel * expansion
    }

    var compactOpacity: Double {
        Double(1 - expansion)
    }

    /// Stops hidden TimelineView work only after the wing is fully gone.
    var runsCompactAnimation: Bool {
        expansion < 1
    }

    var expandedOpacity: Double {
        Double(expansion)
    }

    var expandedOffsetY: CGFloat {
        -Self.listArrivalDistance * (1 - expansion)
    }
}

/// Shared timing for the shell shape and overview content.
///
/// Opening may overshoot slightly; closing is critically damped so the surface
/// never reveals a gap around the physical notch.
enum NotchPresentationAnimation {
    static func animation(expanding: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return expanding
            ? .spring(response: 0.42, dampingFraction: 0.85)
            : .spring(response: 0.34, dampingFraction: 1)
    }
}
