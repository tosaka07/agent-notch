import SwiftUI

/// A notification row that responds to hover, click, and keyboard focus.
struct NotificationRowButton: View {
    let content: AnyView
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    /// The pressable surface, shown only on focus or hover.
    /// Showing it always turns a run of notification rows into a wall of surfaces, and which one
    /// is selected stops reading.
    @ViewBuilder
    private var background: some View {
        if isFocused {
            DSSurfaceFill(.raisedSelected)
        } else if isHovered {
            DSSurfaceFill(.raisedHover)
        }
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(background)
        .clipShape(DSShape.rounded(DSShape.inset))
        .overlay(
            DSShape.rounded(DSShape.inset)
                .strokeBorder(
                    isFocused ? Color.blue.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(DSShape.rounded(DSShape.inset))
        .onHover { isHovered = $0 }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
