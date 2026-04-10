import SwiftUI

/// A notification row that responds to hover, click, and keyboard focus.
struct NotificationRowButton: View {
    let content: AnyView
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isFocused { return Color.white.opacity(0.10) }
        if isHovered { return Color.white.opacity(0.06) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isFocused ? Color.blue.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
