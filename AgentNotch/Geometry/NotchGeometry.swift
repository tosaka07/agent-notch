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

    /// Whether the given point (in screen coordinates) is within the notch area.
    /// Padding extends horizontally and upward only — no downward padding,
    /// so the notch hit zone doesn't overlap with session cards below.
    func isPointInNotch(
        _ point: CGPoint,
        horizontalPadding: CGFloat = 10
    ) -> Bool {
        let rect = notchScreenRect
        let paddedRect = CGRect(
            x: rect.origin.x - horizontalPadding,
            y: rect.origin.y,
            width: rect.width + horizontalPadding * 2,
            height: rect.height
        )
        return paddedRect.contains(point)
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
            let compactWidth = notchSize.width + 400  // 200px padding each side
            let compactHeight = notchSize.height
            let x = screenFrame.midX - compactWidth / 2
            let y = screenFrame.maxY - compactHeight
            return CGRect(x: x, y: y, width: compactWidth, height: compactHeight)
        }
    }
}
