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
                        DotMatrix(
                            pattern: leftWingPattern(primary),
                            animationStartTime: primary.doneAt
                        )
                    }
                }
                .frame(width: wingInner, height: notchHeight)

                // Center: tool name / subagent ticker
                ZStack {
                    // status は tool イベントで頻繁に切り替わるため、subagent の実行有無で判定する
                    if let primary, primary.runningSubagentCount > 0 {
                        TimelineView(.periodic(from: .now, by: 2.5)) { context in
                            if let text = subagentTickerText(primary, at: context.date) {
                                TickerText(
                                    text: text,
                                    font: DSTypography.mono(10, weight: .medium),
                                    color: DSColors.inkDim
                                )
                            }
                        }
                    } else if let toolName = activeToolName(sessions) {
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
                            totalColor: DSColors.ink.opacity(0.55)
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

    /// 左翼 DotMatrix に表示するパターン。
    ///
    /// subagent 実行中のセッションが完了すると `dotPattern` は即座に `.complete`（チェックマーク）を
    /// 返すが、完了直後は完了通知バナーがまさに表示されるタイミングであり、
    /// 直前まで表示していた swarm（subagent 並行実行）表示が完了チェックマークに
    /// 突然置き換わって見える（#12）。完了通知が表示されている間は swarm 表示を維持し、
    /// 通知が消えたタイミングで通常の完了表示に戻す。
    private func leftWingPattern(_ primary: UnifiedSession) -> DotPattern {
        if primary.status == .done,
           primary.subagentCountAtCompletion > 0,
           notificationManager.items.contains(where: { $0.id == primary.id }) {
            return .swarm(active: primary.subagentCountAtCompletion)
        }
        return primary.dotPattern
    }

    private func activeToolName(_ sessions: [UnifiedSession]) -> String? {
        sessions.lazy
            .compactMap { $0.currentTool }
            .first { $0.status == .running }
            .map(\.name)
    }

    /// 実行中 subagent の agentType を集計し `×N TYPE` 形式のテキストを返す。
    /// 複数種ある場合は呼び出し側の `TimelineView(.periodic(by: 2.5))` の日時を使って巡回する。
    private func subagentTickerText(_ session: UnifiedSession, at date: Date) -> String? {
        let running = session.subagents.filter { $0.status == .running }
        guard !running.isEmpty else { return nil }
        let counts = Dictionary(grouping: running, by: \.agentType).mapValues(\.count)
        let types = counts.keys.sorted()
        guard !types.isEmpty else { return nil }
        let index = Int(date.timeIntervalSinceReferenceDate / 2.5) % types.count
        let type = types[index]
        return "×\(counts[type] ?? 0) \(type.uppercased())"
    }
}
