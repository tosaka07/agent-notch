import CoreGraphics

/// Row metrics for the timeline.
///
/// Shared by messages (`ChatMessageView`), tools (`ToolLogRow`), and the running
/// row (`ActiveToolIndicator`). If all three carried their own numbers, fixing
/// one would knock the columns out of alignment.
///
/// ```
/// │← marker →│
///  ●   CLAUDE CODE                        14:53:16
///      Understood. Starting work now.
///  ›   READ ×3  Glyph0.swift · 3 lines    14:54:56
/// │← contentIndent →│
/// ```
///
/// # One marker column
/// **`›` and `●` share a single column, centered.** Messages have no
/// disclosure and tools have no dot, so any given row shows exactly one of
/// them. Giving each its own box would draw `›` at the column's left edge and
/// `●` at its right, leaving two misaligned streaks running down the view.
///
/// # Content stays out of that column
/// Letting body text creep into the marker column makes it look like the text
/// hangs beneath the marker, reading as one level deeper. Content aligns with
/// the label's left edge (= marker + spacing).
enum TimelineMetrics {
    /// Spacing within a row.
    static let spacing: CGFloat = 7
    /// Diameter of the status dot.
    static let dot: CGFloat = 6
    /// Width of the marker column (`›` or `●`), sized to fit the chevron glyph.
    static let marker: CGFloat = 10
    /// Content indent, matching the label's left edge.
    static let contentIndent: CGFloat = marker + spacing
}
