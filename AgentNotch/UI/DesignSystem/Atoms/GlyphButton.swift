import Defaults
import SwiftUI

/// A decision button inside a panel (approve / deny / send).
///
/// System controls such as `.borderedProminent` look like **an OS dialog wedged in**
/// when placed on the black, dot-glyph panel. Build these the same way as the timeline
/// and cards — black ground, hairline border, mono uppercase — so they read as part of the panel.
///
/// # Hierarchy
/// - `isProminent`: the primary decision (APPROVE / SEND). Faint `tint` fill + brighter border
/// - otherwise: the secondary decision (DENY / DISMISS). Border only
///
/// Signal colors are never used for area, so the fill stays at 12% and the border and text carry it.
struct GlyphButton: View {
    let label: String
    /// A typed key chord. `KeyHint` gives each physical key its own bordered cap.
    var shortcut: ShortcutChord?
    /// Primary color, used for the border, text, and faint fill.
    var tint: Color = DSColors.ink
    var isProminent: Bool = false
    var isEnabled: Bool = true
    /// Replaces the label with SwiftUI's standard indeterminate progress view
    /// while preserving the label's layout width.
    var isLoading: Bool = false
    /// Flash right after the press: while true, the fill and border step up one level.
    ///
    /// The pressed state is **supplied by the caller** rather than kept in the button's own
    /// `@State`, so a hotkey press also shows which button was activated.
    var isFlashing: Bool = false
    var action: () -> Void

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var labelColor: Color {
        guard isEnabled else { return DSColors.inkMute }
        // The color never changes on press; only the fill and border respond.
        return isProminent || isFlashing ? tint : DSColors.inkDim
    }

    private var borderColor: Color {
        guard isEnabled else { return DSColors.lineFaint }
        if isFlashing { return tint.opacity(0.9) }
        return isProminent ? tint.opacity(0.5) : DSColors.lineStrong
    }

    /// The press cue is **only one step darker fill**. Flooding it with `tint` stains the screen
    /// for an instant, and the surprise outweighs the reassurance of having pressed.
    private var fillColor: Color {
        guard isEnabled else { return .clear }
        if isFlashing { return tint.opacity(0.28) }
        return isProminent ? tint.opacity(0.12) : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Text(label)
                        .font(DSTypography.mono(s(10), weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(labelColor)
                        .opacity(isLoading ? 0 : 1)

                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(labelColor)
                    }
                }
                if let shortcut {
                    KeyHint(chord: shortcut, isEnabled: isEnabled)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(fillColor)
            .overlay(
                DSShape.rounded(DSShape.inset)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .clipShape(DSShape.rounded(DSShape.inset))
            .contentShape(Rectangle())
            // No scaling. Changing the button's size also moves the gap to its neighbor,
            // which reads as "the layout broke" rather than "I pressed it".
            .animation(.easeOut(duration: 0.1), value: isFlashing)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityValue(isLoading ? L("In progress") : "")
    }
}

#Preview("Glyph Buttons") {
    HStack(spacing: 10) {
        GlyphButton(label: "DENY", shortcut: .escape, action: {})
        GlyphButton(
            label: "APPROVE",
            shortcut: .returnKey,
            tint: DSColors.signalDone,
            isProminent: true,
            action: {}
        )
        GlyphButton(
            label: "SEND", tint: DSColors.signalAlert, isProminent: true, isEnabled: false, action: {})
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
