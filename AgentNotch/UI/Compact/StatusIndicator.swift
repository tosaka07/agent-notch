import AgentNotchCore
import SwiftUI

struct StatusIndicator: View {
    let status: SessionStatus
    var size: CGFloat = 8

    @State private var isAnimating = false

    var body: some View {
        indicator
            .frame(width: size, height: size)
            .animation(animationForStatus, value: isAnimating)
            .onAppear { isAnimating = true }
            .onChange(of: status) { _, _ in
                isAnimating = false
                withAnimation { isAnimating = true }
            }
    }

    @ViewBuilder
    private var indicator: some View {
        switch status {
        case .permissionWaiting:
            // Warning triangle for permission
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(status.color)
                .scaleEffect(isAnimating ? 1.2 : 0.8)

        case .done:
            // Checkmark for done
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(status.color)
                .opacity(isAnimating ? 0 : 1)

        case .error:
            // X for error
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(status.color)
                .scaleEffect(isAnimating ? 1.3 : 0.7)

        default:
            // Dot for all other states
            Circle()
                .fill(status.color)
                .scaleEffect(scaleValue)
        }
    }

    private var scaleValue: CGFloat {
        switch status {
        case .idle, .starting, .completed:
            1.0
        case .thinking:
            isAnimating ? 1.3 : 0.8
        case .toolRunning, .subagentRunning:
            isAnimating ? 1.2 : 0.85
        case .compacting:
            isAnimating ? 1.15 : 0.9
        default:
            1.0
        }
    }

    private var animationForStatus: Animation? {
        switch status {
        case .idle, .starting, .completed:
            nil
        case .thinking:
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        case .toolRunning:
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        case .subagentRunning:
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .permissionWaiting:
            .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
        case .compacting:
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .done:
            .easeOut(duration: 3.0)
        case .error:
            .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
        }
    }
}
