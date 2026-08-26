import SwiftUI

/// A text view that animates changes with a vertical slide (slot-machine style).
struct TickerText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var displayedText: String = ""
    @State private var animationID = UUID()

    var body: some View {
        Text(displayedText)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .id(animationID)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
            .onAppear {
                displayedText = text
            }
            .onChange(of: text) { _, newValue in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    animationID = UUID()
                    displayedText = newValue
                }
            }
    }
}
