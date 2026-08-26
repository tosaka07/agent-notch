import CoreGraphics

/// Stable layout bounds shared by the AppKit window and the SwiftUI surface.
///
/// Individual notch modes never resize this stage. They only change the
/// centered shape drawn inside it.
enum NotchPresentationLayout {
    static let stageSize = CGSize(width: 640, height: 520)
    static let expandedSize = CGSize(width: 520, height: 380)
}

struct NotchSurfaceMetrics: Equatable {
    let width: CGFloat
    let height: CGFloat
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    init(
        width: CGFloat,
        height: CGFloat,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) {
        self.width = width
        self.height = height
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var shape: CenteredNotchShape {
        CenteredNotchShape(
            width: width,
            height: height,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }
}
