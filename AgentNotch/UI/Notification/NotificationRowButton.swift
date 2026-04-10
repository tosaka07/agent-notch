import SwiftUI

/// A notification row that responds to hover, click, and keyboard focus.
struct NotificationRowButton: View {
    let content: AnyView
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var highlightColor: Color {
        if isFocused { return Color.blue.opacity(0.15) }
        if isHovered { return Color.white.opacity(0.08) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(highlightColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    isFocused
                        ? RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                        : nil
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
