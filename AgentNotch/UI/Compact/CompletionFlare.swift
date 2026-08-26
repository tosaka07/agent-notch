import SwiftUI

/// Animated gradient border that flows around the notch shape on session completion.
/// Uses an angular gradient with the base color and neighboring hues, rotating continuously.
struct CompletionFlare: View {
    let shape: NotchGlowBorder
    let color: Color
    let intensity: CGFloat  // 0…1, controls master opacity

    @State private var rotation: CGFloat = 0

    /// Generate a rich palette from the base color and its neighbors on the hue wheel.
    private var gradientColors: [Color] {
        let neighbors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.0, 1.0, 1.0),  // base
            (-0.06, 0.8, 1.0),  // cooler neighbor
            (-0.12, 0.6, 0.9),  // further cool
            (0.0, 1.0, 1.0),  // base again
            (0.06, 0.8, 1.0),  // warmer neighbor
            (0.12, 0.6, 0.9),  // further warm
            (0.0, 1.0, 1.0),  // base (close loop)
        ]
        return neighbors.map { offset, sat, bri in
            shiftHue(color, by: offset, saturationScale: sat, brightnessScale: bri)
        }
    }

    var body: some View {
        ZStack {
            // Core bright border
            shape
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: 2.5
                )

            // Soft wider glow layer
            shape
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        angle: .degrees(rotation + 60)
                    ),
                    lineWidth: 5
                )
                .blur(radius: 6)
                .opacity(0.6)
        }
        .opacity(intensity)
        .onChange(of: intensity) { _, newVal in
            if newVal > 0 && rotation == 0 {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    /// Shift a Color's hue by a fraction (e.g. +0.05 = 5% warmer on the color wheel).
    private func shiftHue(
        _ color: Color, by hueOffset: CGFloat, saturationScale: CGFloat, brightnessScale: CGFloat
    ) -> Color {
        let nsColor = NSColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        converted.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newH = (h + hueOffset).truncatingRemainder(dividingBy: 1.0)
        return Color(
            hue: newH < 0 ? newH + 1 : newH,
            saturation: min(s * saturationScale, 1),
            brightness: min(b * brightnessScale, 1),
            opacity: a)
    }
}
