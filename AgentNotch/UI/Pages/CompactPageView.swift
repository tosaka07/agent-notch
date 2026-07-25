import AgentNotchCore
import SwiftUI

/// `compact` / `notification` モードの UI。
///
/// # 情報の居場所
/// - Left wing: `StateGlyphView` — 最優先セッションの状態を 13×13 のドットグリフで表現
/// - Center: **物理 notch がある画面では隠れて見えない**ので何も置かない。
///   notch なし（フローティングバー表示）のときだけツール名 ticker を出す
/// - Right wing: `PixelCounter` — running / total
///
/// # 設計原則
/// - 翼に置けるのはグリフだけ（テキストは置かない）
/// - 色が消えても形で状態が読める（グリフの図柄の違い）
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

                // Left wing: 状態グリフ
                ZStack {
                    if let primary {
                        StateGlyphView(
                            state: leftWingState(primary),
                            size: min(wingInner, notchHeight - 12),
                            animationStartTime: primary.doneAt
                        )
                    }
                }
                .frame(width: wingInner, height: notchHeight)

                // Center: 物理 notch と重なる領域。notch がある画面では見えないので出さない。
                ZStack {
                    if !viewModel.hasPhysicalNotch {
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

    /// 左翼に表示する状態グリフ。
    ///
    /// subagent 実行中のセッションが完了すると `dotPattern` は即座に `.complete`（チェックマーク）を
    /// 返すが、完了直後は完了通知バナーがまさに表示されるタイミングであり、
    /// 直前まで表示していた swarm（subagent 並行実行）表示が完了チェックマークに
    /// 突然置き換わって見える（#12）。完了通知が表示されている間は swarm 表示を維持し、
    /// 通知が消えたタイミングで通常の完了表示に戻す。
    private func leftWingState(_ primary: UnifiedSession) -> Glyph.State {
        // 完了通知バナーは enqueue と同時に mode を `.notification` に切り替えるため
        // （NotchEventRouter.handleSessionCompleted/handleSessionSwept）、mode を先に
        // ガードすることで compact モードの body 再評価が notificationManager.items の
        // 変化に巻き込まれないようにする。
        guard viewModel.mode == .notification,
              primary.status == .done,
              primary.subagentCountAtCompletion > 0,
              notificationManager.items.contains(where: { $0.id == primary.id })
        else {
            return primary.glyphState
        }
        return .swarm(active: primary.subagentCountAtCompletion)
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
