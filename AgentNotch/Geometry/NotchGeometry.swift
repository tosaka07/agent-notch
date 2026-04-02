import Foundation

struct NotchGeometry: Sendable {
    let notchSize: CGSize
    let screenFrame: CGRect

    /// The notch rectangle in screen coordinates, centered at the top of the screen.
    var notchScreenRect: CGRect {
        let x = screenFrame.midX - notchSize.width / 2
        let y = screenFrame.maxY - notchSize.height
        return CGRect(x: x, y: y, width: notchSize.width, height: notchSize.height)
    }

    /// Whether the given point (in screen coordinates) is within the notch area,
    /// including configurable padding.
    func isPointInNotch(
        _ point: CGPoint,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 5
    ) -> Bool {
        let paddedRect = notchScreenRect.insetBy(
            dx: -horizontalPadding,
            dy: -verticalPadding
        )
        return paddedRect.contains(point)
    }

    /// Whether the given point is within the window frame for the current mode.
    func isPointInWindow(
        _ point: CGPoint,
        isExpanded: Bool,
        expandedWidth: CGFloat = 650,
        expandedHeight: CGFloat = 500
    ) -> Bool {
        let frame = windowFrame(
            expandedWidth: expandedWidth,
            expandedHeight: expandedHeight,
            isExpanded: isExpanded
        )
        return frame.contains(point)
    }

    /// Computes the window frame based on expansion state.
    /// Compact = notch width + 200px padding on each side.
    /// Expanded = specified width/height, centered at notch.
    func windowFrame(
        expandedWidth: CGFloat = 650,
        expandedHeight: CGFloat = 500,
        isExpanded: Bool
    ) -> CGRect {
        if isExpanded {
            let x = screenFrame.midX - expandedWidth / 2
            let y = screenFrame.maxY - expandedHeight
            return CGRect(x: x, y: y, width: expandedWidth, height: expandedHeight)
        } else {
            let compactWidth = notchSize.width + 400 // 200px padding each side
            let compactHeight = notchSize.height
            let x = screenFrame.midX - compactWidth / 2
            let y = screenFrame.maxY - compactHeight
            return CGRect(x: x, y: y, width: compactWidth, height: compactHeight)
        }
    }
}
