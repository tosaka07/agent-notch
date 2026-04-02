import SwiftUI

struct StatusIndicator: View {
    let status: SessionStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}
