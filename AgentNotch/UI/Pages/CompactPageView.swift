import AgentNotchCore
import SwiftUI

/// `compact` / `notification` モードの UI。
///
/// # 情報の居場所（Design System Phase 1）
/// - Left wing: `DotMatrix` — 最優先セッションの状態を 5×7 bitmap で表現
/// - Center: 現在のツール名 ticker（SF Mono）
/// - Right wing: `PixelCounter` — running / total
///
/// # 設計原則
/// - 色が消えても形で状態が読める（DotPattern の違い）
/// - 通知スタック表示中は DotMatrix を白単色 (`useSignalColor = false`) に落とし、
///   通知側の色（amber / green 等）を主役にする
struct CompactPageView: View {
    let viewModel: NotchViewModel
    let notificationManager: NotchNotificationManager
    let focusController: NotificationFocusController
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        let sessions = sessionManager.activeSessions
        let primary = Self.primarySession(sessions)
        let wing = viewModel.sideWidth
        let notchHeight = viewModel.physicalNotchHeight
        // wing は notch のラウンドコーナー外側まで伸びているため、そのまま使うと Canvas が
        // notch のクリップ領域より外まで広がる。両端に edgeMargin を確保して実効的な
        // 描画領域を notch 可視範囲に収める。
        let edgeMargin: CGFloat = 8
        let wingInner = max(0, wing - edgeMargin)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: edgeMargin)

                // Left wing: DotMatrix
                ZStack {
                    if let primary {
                        DotMatrix(pattern: primary.status.dotPattern)
                    }
                }
                .frame(width: wingInner, height: notchHeight)

                // Center: tool name ticker
                ZStack {
                    if let toolName = activeToolName(sessions) {
                        TickerText(
                            text: toolName,
                            font: DSTypography.mono(10, weight: .medium),
                            color: DSColors.inkDim
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: notchHeight)
                .clipped()

                // Right wing: PixelCounter (value は常に ink で可読、total は inkDim で強度差)
                ZStack {
                    if !sessions.isEmpty {
                        let running = sessions.filter(\.status.isRunning).count
                        PixelCounter(
                            value: running,
                            total: sessions.count,
                            valueColor: DSColors.ink,
                            totalColor: DSColors.inkDim
                        )
                    }
                }
                .frame(width: wingInner, height: notchHeight)

                Color.clear.frame(width: edgeMargin)
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

    // MARK: - Selection helpers

    /// 最優先セッション（urgency 昇順 + lastActivityAt 降順）を返す。
    static func primarySession(_ sessions: [UnifiedSession]) -> UnifiedSession? {
        sessions.min { lhs, rhs in
            if lhs.status.urgencyRank != rhs.status.urgencyRank {
                return lhs.status.urgencyRank < rhs.status.urgencyRank
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    private func activeToolName(_ sessions: [UnifiedSession]) -> String? {
        sessions.lazy
            .compactMap { $0.currentTool }
            .first { $0.status == .running }
            .map(\.name)
    }
}
