import AppKit
import SwiftUI
import Testing

@testable import AgentNotch

@Suite("Session detail surfaces")
@MainActor
struct SessionDetailSurfaceTests {
    /// Renders a view over black and returns the fill just inside its left edge.
    ///
    /// Sampling a fixed coordinate would land on the label, so this walks in
    /// from the left until the background stops being the black canvas.
    private func fill<Content: View>(of view: Content) -> CGFloat? {
        let hostingView = NSHostingView(
            rootView:
                view
                .padding(20)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        hostingView.layoutSubtreeIfNeeded()

        guard
            let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let y = bitmap.pixelsHigh / 2
        for x in 0..<(bitmap.pixelsWide - 3) {
            guard
                let edge = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                edge.redComponent > 0.01
            else { continue }
            return bitmap.colorAt(x: x + 3, y: y)?
                .usingColorSpace(.deviceRGB)?
                .redComponent
        }
        return nil
    }

    @Test("DSColors.control is the tint AppKit paints for a bordered button")
    func controlTintMatchesBorderedButton() throws {
        // `DSSurface.control` — the work context chips — cannot *be* a bordered
        // Button: it grows into a container holding a list, and interactive
        // rows cannot live inside a button's label. Its tint reproduces the
        // value AppKit paints, so pin that rather than trusting the two to
        // drift together. The chip layers the tint over a material as well,
        // because the log scrolls underneath it; only the tint is compared.
        let borderedButton = try #require(
            fill(
                of: Button("Terminal") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            )
        )
        let tint = try #require(
            fill(
                of: Text(verbatim: "TASKS")
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DSColors.control)
                    .clipShape(DSShape.rounded(DSShape.subtle))
            )
        )

        #expect(
            abs(tint - borderedButton) < 0.01,
            "Control tint \(tint) does not match the bordered button's \(borderedButton)"
        )
    }
}
