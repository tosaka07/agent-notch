import AgentNotchCore
import SwiftUI

/// `compact` / `notification` モードの UI。
/// notch の両翼にステータスインジケーター + ツール名、下段に通知スタック（.notification 時のみ）。
struct CompactPageView: View {
    let viewModel: NotchViewModel
    let notificationManager: NotchNotificationManager
    let focusController: NotificationFocusController
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        let sessions = sessionManager.activeSessions
        let urgentStatus = mostUrgentStatus(sessions)
        let wing = viewModel.sideWidth

        VStack(spacing: 0) {
            // Wing row
            HStack(spacing: 0) {
                // Left wing
                ZStack {
                    if !sessions.isEmpty {
                        StatusIndicator(status: urgentStatus, size: 12)
                    }
                }
                .frame(width: wing, height: viewModel.physicalNotchHeight)

                // Center: tool ticker
                ZStack {
                    if let toolName = activeToolName(sessions) {
                        TickerText(
                            text: toolName,
                            font: .system(size: 9, weight: .medium, design: .monospaced),
                            color: .white.opacity(0.6)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: viewModel.physicalNotchHeight)
                .clipped()

                // Right wing: running/total session count
                ZStack {
                    let total = sessions.count
                    let running = sessions.filter(\.status.isRunning).count
                    if total > 0 {
                        VStack(spacing: 0) {
                            Text("\(running)")
                                .foregroundStyle(.white.opacity(running > 0 ? 0.75 : 0.35))
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 12, height: 0.5)
                            Text("\(total)")
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
                .frame(width: wing, height: viewModel.physicalNotchHeight)
            }

            // Notification rows (only in .notification mode)
            if viewModel.mode == .notification {
                VStack(spacing: 0) {
                    ForEach(Array(notificationManager.items.enumerated()), id: \.element.id) { index, item in
                        NotificationRowButton(
                            content: item.content,
                            isFocused: focusController.isFocused && index == focusController.focusIndex
                        ) {
                            item.onTap?()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(width: viewModel.notchWidth)
    }

    private func activeToolName(_ sessions: [UnifiedSession]) -> String? {
        sessions.lazy
            .compactMap { $0.currentTool }
            .first { $0.status == .running }
            .map(\.name)
    }

    private func mostUrgentStatus(_ sessions: [UnifiedSession]) -> SessionStatus {
        let priority: [SessionStatus] = [
            .permissionWaiting, .error, .toolRunning, .subagentRunning,
            .thinking, .compacting, .done, .idle, .starting, .completed,
        ]
        for status in priority {
            if sessions.contains(where: { $0.status == status }) {
                return status
            }
        }
        return .idle
    }
}
