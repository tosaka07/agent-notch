import SwiftUI

/// Multi-layer solar flare glow effect for the notch border on session completion.
struct CompletionFlare: View {
    let shape: NotchGlowBorder
    let color: Color
    let intensity: CGFloat // 0…1, controls master opacity

    // Each layer pulses at a different phase/speed for organic flicker
    @State private var pulse1: CGFloat = 0
    @State private var pulse2: CGFloat = 0
    @State private var pulse3: CGFloat = 0
    @State private var pulse4: CGFloat = 0

    var body: some View {
        ZStack {
            // Layer 0: Ultra-wide ambient haze
            shape
                .stroke(color.opacity(0.15), lineWidth: 16 + pulse4 * 10)
                .blur(radius: 24 + pulse4 * 12)

            // Layer 1: Wide soft glow (corona)
            shape
                .stroke(color.opacity(0.3), lineWidth: 10 + pulse1 * 8)
                .blur(radius: 16 + pulse1 * 10)

            // Layer 2: Medium glow (chromosphere)
            shape
                .stroke(color.opacity(0.5), lineWidth: 6 + pulse2 * 5)
                .blur(radius: 8 + pulse2 * 6)

            // Layer 3: Tight bright core
            shape
                .stroke(color, lineWidth: 2 + pulse3 * 1.5)
                .blur(radius: 1.5)
                .shadow(color: color.opacity(0.9), radius: 6 + pulse3 * 4)
        }
        .opacity(intensity)
        .onAppear { startFlare() }
        .onChange(of: intensity) { _, newVal in
            if newVal > 0 { startFlare() }
        }
    }

    private func startFlare() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            pulse4 = 1
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.15)) {
            pulse1 = 1
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.3)) {
            pulse2 = 1
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(0.45)) {
            pulse3 = 1
        }
    }
}
