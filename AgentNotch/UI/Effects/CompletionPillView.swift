import Defaults
import SwiftUI

/// The completion pill floated **below and outside** the panel when another session finishes in
/// the background while a list screen (expanded / sessionDetail) is up. Tapping opens that
/// session's detail.
///
/// Because it sits outside the panel, directly over the wallpaper, the surface is
/// `DSSurface.floating` (material + a stronger scrim) so it reads on its own, and the outline is
/// secured by a `lineDefault` hairline — it is not glass, so the "draw no border" rule does not
/// apply. The semantic state color (the green of completion) is not painted on the surface; it
/// rides only the dot at the leading edge.
struct CompletionPillView: View {
    let pill: CompletionPill
    let color: Color
    let action: () -> Void

    @Default(.textSize) private var textSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(pill.label)
                    .font(DSTypography.Native.monoCaption(textSize.scale, weight: .medium))
                    .foregroundStyle(DSColors.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(DSSurfaceFill(.floating))
            .clipShape(DSShape.pill)
            .overlay(DSShape.pill.stroke(DSColors.lineDefault, lineWidth: 1))
            .contentShape(DSShape.pill)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 320)
        .accessibilityLabel(L("Completed: \(pill.label). Open session detail"))
    }
}
