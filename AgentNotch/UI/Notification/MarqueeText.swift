import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    var speed: Double = 30 // pt per second
    var onCycleComplete: (() -> Void)?

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false
    @State private var cycleReported = false

    private var needsScroll: Bool { textWidth > containerWidth }

    var body: some View {
        GeometryReader { geo in
            let _ = DispatchQueue.main.async {
                containerWidth = geo.size.width
            }
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { textGeo in
                    Color.clear.onAppear {
                        textWidth = textGeo.size.width
                        startAnimationIfNeeded()
                    }
                })
                .offset(x: offset)
        }
        .clipped()
        .onChange(of: text) {
            offset = 0
            animating = false
            cycleReported = false
            textWidth = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startAnimationIfNeeded()
            }
        }
    }

    private func startAnimationIfNeeded() {
        guard !animating else { return }
        if !needsScroll {
            // No scrolling needed — report immediately
            reportCycleComplete()
            return
        }
        animating = true
        // Initial pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard animating else { return }
            scrollToEnd()
        }
    }

    private func scrollToEnd() {
        let distance = textWidth - containerWidth
        guard distance > 0 else { return }
        let duration = distance / speed

        withAnimation(.linear(duration: duration)) {
            offset = -distance
        }

        // Pause at end, then reset
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5) {
            guard animating else { return }
            // First cycle complete
            reportCycleComplete()

            withAnimation(.easeInOut(duration: 0.3)) {
                offset = 0
            }
            // Restart cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard animating else { return }
                scrollToEnd()
            }
        }
    }

    private func reportCycleComplete() {
        guard !cycleReported else { return }
        cycleReported = true
        onCycleComplete?()
    }
}
