import AgentNotchCore
import Defaults
import SwiftUI

/// 使用率を表す小さな常時表示ゲージ。
///
/// `ExpandedPageView`（セッション一覧）のトップバー左翼に、エージェントごとに 1 つずつ横並びで
/// 常設する想定。ここは compact モードの `DotMatrix` と同じ「notch の翼」そのものの位置であり、
/// パネル内部（#37 の Native 化対象）とは違って独自のピクセル言語を保つ場所のため、
/// 標準 SwiftUI の `Circle`/`Text` ではなく `PixelGrid` + `DotCell`（compact 側と共通の
/// 描画基盤）で描く。
///
/// # 表示形式（`Defaults[.usageGaugeStyle]`、設定から選択）
/// - `.ring`: 13×13 グリッド上に円環状に並んだ 28 ドット（`ringPoints`。中心 (6,6) 半径 5）を
///   使用率に応じて 12 時位置から時計回りに点灯させる。
/// - `.number`: `PixelCounter.drawTwoDigit` の 5×4 digit bitmap を再利用して 2 桁を中央に描く。
///
/// `usedPercent` が nil のとき（初回ポーリング前）は、リングの輪郭だけを薄く描いた
/// プレースホルダを出す。何も出さないと「ゲージが無い」ように見えて違和感があるため。
///
/// # 色
/// 点灯ドットは使用率のしきい値で 70% → `signalAlert` / 90% → `signalError` にエスカレーション
/// する（形と色の両方で読める独自言語のルール）。未点灯ドットは `agentType` の色を薄く敷いて
/// 「どのエージェントのゲージか」を色相で示す（Claude と Codex を横並びにするため）。
///
/// # 操作
/// クリックは呼び出し側の責務（使用量詳細ページへの遷移に割り当てている）。この View 自体は
/// タップ処理を持たない純粋な表示コンポーネントなので、Button の label としても使える。
struct UsageGauge: View {
    /// 0〜100 の使用率。未取得（ローディング中）は nil。
    let usedPercent: Double?
    /// どのエージェントの使用率か。未点灯ドットの色相で識別に使う。nil なら中立色。
    var agentType: AgentType?
    /// グリッド全体の一辺のサイズ。compact 左翼の `DotMatrix`（cellSize 1.6 → 13×1.6≈21pt）に揃える。
    var size: CGFloat = 21

    @Default(.usageGaugeStyle) private var style

    private var clampedPercent: Double { min(max(usedPercent ?? 0, 0), 100) }

    /// 点灯ドット（使用済み部分・数字）の色。
    private var valueColor: Color {
        switch clampedPercent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: .secondary
        }
    }

    /// 未点灯ドット（リングの残り）の色。エージェントの色相を薄く敷いて識別に使う。
    private var trackColor: Color {
        (agentType?.color ?? .secondary).opacity(0.3)
    }

    private var cellSize: CGFloat { size / CGFloat(PixelGrid.dimension) }

    var body: some View {
        PixelGrid(cells: cells, cellSize: cellSize)
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(agentType.map { "\($0.displayName) の使用率" } ?? "使用率")
            .accessibilityValue(
                usedPercent == nil ? "取得中" : "\(Int(clampedPercent.rounded()))パーセント"
            )
    }

    /// 表示形式に応じてリング / 数字を描いた 13×13 セル。
    /// 未取得（`usedPercent == nil`）のときは輪郭だけのプレースホルダ。
    private var cells: [[DotCell]] {
        var cells = DotBitmap.emptyCellGrid()
        guard usedPercent != nil else {
            drawRingTrack(into: &cells)
            return cells
        }
        switch style {
        case .ring: drawRing(into: &cells)
        case .number: drawNumber(into: &cells)
        }
        return cells
    }

    // MARK: - Ring

    /// 中心 (6,6) 半径 5 の midpoint circle を 12 時位置（真上）から時計回りに並べた 28 点。
    ///
    /// 半径 6 だと上下左右（`(0,6)` 等）が円の輪郭から 1 セルだけ孤立して飛び出して見える
    /// （真下の `(1,6)` が輪郭に含まれず、棘のようになる）。半径 5 は輪郭が rows/cols 1〜11 に
    /// 収まり、上下左右も 3 セル並ぶ（`....#####....`）ため飛び出しが起きない。
    /// 内側の rows 4〜8 × cols 2〜10 には 1 点も入らないので、数字（`drawNumber`）と
    /// 座標が競合しない。
    private static let ringPoints: [(row: Int, col: Int)] = [
        (1, 6), (1, 7), (1, 8), (2, 9), (3, 10), (4, 11), (5, 11), (6, 11),
        (7, 11), (8, 11), (9, 10), (10, 9), (11, 8), (11, 7), (11, 6), (11, 5),
        (11, 4), (10, 3), (9, 2), (8, 1), (7, 1), (6, 1), (5, 1), (4, 1),
        (3, 2), (2, 3), (1, 4), (1, 5),
    ]

    /// 輪郭だけを `trackColor` で描く（ローディング中のプレースホルダ）。
    private func drawRingTrack(into cells: inout [[DotCell]]) {
        for point in Self.ringPoints {
            cells[point.row][point.col] = .on(color: trackColor)
        }
    }

    private func drawRing(into cells: inout [[DotCell]]) {
        let litCount = Int((clampedPercent / 100 * Double(Self.ringPoints.count)).rounded())
        for (index, point) in Self.ringPoints.enumerated() {
            let dotColor = index < litCount ? valueColor : trackColor
            cells[point.row][point.col] = .on(color: dotColor)
        }
    }

    // MARK: - Number

    private func drawNumber(into cells: inout [[DotCell]]) {
        // 2桁までしか描けないため 100% は 99 に丸める。
        let value = min(99, Int(clampedPercent.rounded()))
        PixelCounter.drawTwoDigit(value, rowOffset: 4, color: valueColor, into: &cells)
    }
}

#Preview("Usage Gauge") {
    VStack(spacing: 20) {
        ForEach([12.0, 78.0, 95.0], id: \.self) { percent in
            HStack(spacing: 20) {
                UsageGauge(usedPercent: percent, agentType: .claudeCode, size: 32)
                UsageGauge(usedPercent: percent, agentType: .codex, size: 32)
                Text("\(Int(percent))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(24)
    .background(Color.black)
}
