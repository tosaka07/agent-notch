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

    // Physical notch dimensions — set from NSScreen on init
    var physicalNotchWidth: CGFloat = 224
    var physicalNotchHeight: CGFloat = 38

    // Whether any session is active (controls wing expansion)
    var hasActivity: Bool = false

    /// Wing size on each side (Claude Island style: notchHeight - 12 + 10)
    var sideWidth: CGFloat {
        max(0, physicalNotchHeight - 12) + 10
    }

    /// Extra width beyond the physical notch
    private var expansionWidth: CGFloat {
        hasActivity ? (2 * sideWidth + 20) : 0
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact: physicalNotchWidth + expansionWidth
        case .expanded: 550
        case .fullPanel: 650
        }
    }

    var notchHeight: CGFloat {
        switch mode {
        case .compact: physicalNotchHeight
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
    @State var sessionManager: SessionManager

    private var animation: Animation {
        // Open: bouncy spring. Close: no bounce (dampingFraction 1.0) to avoid shrinking below notch
        viewModel.mode == .compact
            ? .spring(response: 0.45, dampingFraction: 1.0)
            : .spring(response: 0.42, dampingFraction: 0.8)
    }

    /// Directly reference activeSessions in body so @Observable tracking kicks in
    private var sessions: [UnifiedSession] {
        sessionManager.activeSessions
    }

    var body: some View {
        let hasSessions = !sessions.isEmpty

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
            .animation(.smooth, value: viewModel.hasActivity)

            contentForMode
                .animation(animation, value: viewModel.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hasSessions) { _, newValue in
            viewModel.hasActivity = newValue
        }
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

    /// Compact mode (Claude Island style):
    /// - No activity: notch-sized black shape, invisible behind physical notch
    /// - Active: wings extend from notch — left wing has status icon, right wing has spinner/info
    @ViewBuilder
    private var compactContent: some View {
        let sessions = sessionManager.activeSessions

        if sessions.isEmpty {
            // No sessions — invisible behind the physical notch
            EmptyView()
                .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        } else {
            HStack(spacing: 0) {
                // Left wing: agent status icon
                HStack(spacing: 4) {
                    StatusIndicator(status: sessions.first?.status ?? .idle, size: 10)
                    if sessions.count > 1 {
                        // Multiple sessions: show count
                        Text("\(sessions.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: viewModel.sideWidth)

                // Center: notch area (black spacer)
                Color.black
                    .frame(width: viewModel.physicalNotchWidth - viewModel.topCornerRadius)

                // Right wing: current tool or spinner
                HStack(spacing: 4) {
                    if let tool = sessions.first?.currentTool {
                        Text(tool.summary)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    } else {
                        Text(sessions.first?.status.label ?? "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(width: viewModel.sideWidth)
            }
            .frame(height: viewModel.notchHeight)
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
