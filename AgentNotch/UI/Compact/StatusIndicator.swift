import SwiftUI

struct StatusIndicator: View {
    let status: SessionStatus
    var size: CGFloat = 8

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .scaleEffect(scaleValue)
            .opacity(opacityValue)
            .animation(animationForStatus, value: isAnimating)
            .onAppear { isAnimating = true }
            .onChange(of: status) { _, _ in
                isAnimating = false
                withAnimation { isAnimating = true }
            }
    }

    private var scaleValue: CGFloat {
        switch status {
        case .idle, .starting:
            return 1.0
        case .thinking:
            return isAnimating ? 1.3 : 0.8
        case .toolRunning:
            return isAnimating ? 1.2 : 0.9
        case .permissionWaiting:
            return isAnimating ? 1.4 : 0.7
        case .error:
            return isAnimating ? 1.5 : 0.5
        case .compacting:
            return isAnimating ? 1.2 : 0.9
        case .completed:
            return 1.0
        }
    }

    private var opacityValue: Double {
        switch status {
        case .completed:
            return isAnimating ? 0.0 : 1.0
        default:
            return 1.0
        }
    }

    private var animationForStatus: Animation? {
        switch status {
        case .idle, .starting:
            return nil
        case .thinking:
            return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .toolRunning:
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .permissionWaiting:
            return .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        case .error:
            return .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
        case .compacting:
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .completed:
            return .easeOut(duration: 2.0)
        }
    }
}
