import SwiftUI

enum NotchMode: Sendable {
    case compact
    case expanded
    case fullPanel
}

@MainActor
@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact

    var notchWidth: CGFloat {
        switch mode {
        case .compact: 224
        case .expanded: 550
        case .fullPanel: 650
        }
    }

    var notchHeight: CGFloat {
        switch mode {
        case .compact: 38
        case .expanded: 400
        case .fullPanel: 500
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact: 6
        case .expanded, .fullPanel: 19
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .expanded, .fullPanel: 24
        }
    }

    func toggle() {
        switch mode {
        case .compact:
            mode = .expanded
        case .expanded:
            mode = .fullPanel
        case .fullPanel:
            mode = .compact
        }
    }

    func close() {
        mode = .compact
    }
}

struct NotchContentView: View {
    @State var viewModel = NotchViewModel()
    var sessionManager: SessionManager

    private let animation: Animation = .spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(
                topCornerRadius: viewModel.topCornerRadius,
                bottomCornerRadius: viewModel.bottomCornerRadius
            )
            .fill(.black)
            .frame(
                width: viewModel.notchWidth,
                height: viewModel.notchHeight
            )
            .animation(animation, value: viewModel.mode)

            contentForMode
                .animation(animation, value: viewModel.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch viewModel.mode {
        case .compact:
            compactContent
        case .expanded:
            expandedContent
        case .fullPanel:
            fullPanelContent
        }
    }

    // MARK: - Compact

    @ViewBuilder
    private var compactContent: some View {
        let sessions = sessionManager.activeSessions
        if sessions.isEmpty {
            Text("Agent Notch")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        } else {
            HStack(spacing: 6) {
                ForEach(sessions.prefix(4)) { session in
                    HStack(spacing: 3) {
                        StatusIndicator(status: session.status, size: 6)

                        if let tool = session.currentTool {
                            Text(tool.summary)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        } else {
                            Text(session.status.label)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 8) {
            Text("Sessions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 44)

            let sessions = sessionManager.activeSessions
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
    }

    // MARK: - Full Panel

    private var fullPanelContent: some View {
        VStack(spacing: 8) {
            Text("Agent Notch")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 44)

            let sessions = sessionManager.activeSessions
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(sessions) { session in
                            sessionCardFull(session)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
    }

    // MARK: - Session Cards

    private func sessionCard(_ session: UnifiedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusIndicator(status: session.status, size: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let model = session.model {
                Text(model)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if let tool = session.currentTool {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8))
                    Text("\(tool.name): \(tool.summary)")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.green.opacity(0.8))
            }

            HStack(spacing: 12) {
                Label(
                    TokenFormatter.format(session.totalInputTokens),
                    systemImage: "arrow.down"
                )
                Label(
                    TokenFormatter.format(session.totalOutputTokens),
                    systemImage: "arrow.up"
                )
                Spacer()
                Text(CostCalculator.formatCost(session.estimatedCost))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sessionCardFull(_ session: UnifiedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                StatusIndicator(status: session.status, size: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let model = session.model {
                Text(model)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if let tool = session.currentTool {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8))
                    Text("\(tool.name): \(tool.summary)")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.green.opacity(0.8))
            }

            // Token stats
            HStack(spacing: 12) {
                Label(
                    TokenFormatter.format(session.totalInputTokens),
                    systemImage: "arrow.down"
                )
                Label(
                    TokenFormatter.format(session.totalOutputTokens),
                    systemImage: "arrow.up"
                )
                Spacer()
                Text(CostCalculator.formatCost(session.estimatedCost))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))

            // Recent tools history
            if !session.recentTools.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Tools")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    ForEach(session.recentTools.suffix(5)) { tool in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tool.status == .succeeded ? Color.green : Color.red)
                                .frame(width: 4, height: 4)
                            Text("\(tool.name): \(tool.summary)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
