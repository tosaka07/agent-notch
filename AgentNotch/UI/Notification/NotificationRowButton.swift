import SwiftUI

/// A notification row that responds to hover and click.
struct NotificationRowButton: View {
    let content: AnyView
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}
