import SwiftUI

struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 4

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color.opacity(pulse ? 0.9 : 0.35))
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
