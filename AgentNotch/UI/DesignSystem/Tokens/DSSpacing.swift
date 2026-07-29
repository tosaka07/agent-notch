import SwiftUI

/// Spacing tokens on an 8pt grid, for the panel (list and detail screens).
///
/// The notch's own language (compact mode) may keep using fine-grained values for density, but
/// new and revised code inside the panel should pick from these to keep spacing consistent.
enum DSSpacing {
    /// 4pt — the minimum gap between inline elements (an icon and its label, etc.)
    static let xs: CGFloat = 4
    /// 8pt — the grid unit. The baseline spacing within a row
    static let sm: CGFloat = 8
    /// 12pt — vertical spacing inside a card
    static let md: CGFloat = 12
    /// 16pt — between sections, and a card's outer padding
    static let lg: CGFloat = 16
    /// 24pt — the larger section gap
    static let xl: CGFloat = 24
}
