import AppKit
import SwiftUI

/// 使用量の目盛り（Claude Design モック 2b / 3b）。
///
/// グリフ辞書の D（3×3 ブロック）を 10 個並べて 100% を表す。**1 ブロック = 10%**。
/// 連続的なバーではなく離散的なブロックにするのは、
/// - 「あと何ブロック残っているか」が数として読める
/// - **severity は色だけを変え、目盛りは変えない**ので、API 由来の severity と
///   自前のしきい値が同じ目盛りに乗る
/// という 2 点のため。
struct UsageBlockScale: View {
    /// 0〜100 の使用率。
    let usedPercent: Double
    /// 消費済みブロックの色。severity で変えるのは色だけ。
    var color: Color = DSColors.ink
    /// ブロック数。10 個 = 100%（1 個 10%）。
    var blocks: Int = 10
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// ブロック間の間隔。
    var spacing: CGFloat = 5

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<blocks, id: \.self) { index in
                GlyphView(
                    bitmap: Glyph.usageBlock(
                        filled: Double(index) / Double(blocks) < clampedPercent / 100 - 0.001,
                        color: color
                    ),
                    dot: dot,
                    gap: gap
                )
            }
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(clampedPercent.rounded()))パーセント")
    }
}

/// 日毎コストのドットチャート（モック 3b）。
///
/// 1 列 = 1 日。**1 段 = 3×3 のブロックグリフ**を下から積み上げて高さで量を表す。
/// 消費済みは塗り（■）、残量は輪郭（□）なので、グリフ辞書の D と同じ読み方になる。
/// 値があれば最低 1 段は点灯させるので、少額の日が「無い」ように見えない。
/// 最新の列だけ色を強めて「今日」が分かるようにする。
///
/// # なぜ 1 段を 3×3 にするのか
/// 1 段 = 1 ドットだと、ドットを細かく保ったままではチャートが小さくなりすぎて
/// カードの左に寄ってしまう。**ドットは 2pt のまま、単位を 3×3 にまとめる**ことで、
/// 目の粗さを変えずに図を 2 倍近く大きくできる。
/// 全体は 1 枚のビットマップとして組むので、描画は `GlyphView` 一発で済む。
///
/// # 軸を持たせる
/// 目盛りを外に置くと「図がただ置いてある」状態になり、どの列がいつなのか、
/// 天井がいくらなのかが読めない。そこでラベルをチャート自身に持たせる:
/// - **縦軸**: 最上段の行にピーク金額、最下段の行に 0。行の高さに合わせて置くので
///   「この高さが 12 ドル」と読める
/// - **横軸**: 左端・右端の列の真下に日付。チャート幅に揃えるので列と対応が取れる
struct UsageBlockChart: View {
    /// 左から古い順の値。
    let values: [Double]
    /// 左端の列（最も古い日）の目盛りラベル。
    var startLabel: String?
    /// 右端の列（最新日）の目盛りラベル。
    var endLabel: String?
    /// 縦軸の天井に添えるラベル（ピーク金額など）。
    var peakLabel: String?
    /// 立ち上がりの進捗（0〜1）。
    ///
    /// 1 未満のとき、各列は**下から目標の高さへ伸びる途中**として描かれる。
    /// 左の列から少し遅れて始まるので、波が引いたあとに値が満ちていくように見える
    /// （ローディングの波からそのまま繋がる）。
    var revealProgress: Double = 1
    /// ローディング中の位相（0〜1）。
    ///
    /// 値を渡すと `values` の代わりに**左から右へ流れる波**を描く。空の格子を静止させておくと
    /// 「集計が終わってこの結果だった（＝全部 0）」と読み違えるため、数として読めない
    /// 動きに置き換える（ゲージの回るリングと同じ考え方）。
    var loadingPhase: Double?
    /// 1 列あたりの段数（縦の解像度）。
    var blocksPerColumn: Int = 7
    var color: Color = DSColors.ink.opacity(0.62)
    var latestColor: Color = DSColors.ink
    /// ドット 1 個の辺。3×3 で 1 段になるので、段の高さは `dot * 3 + gap * 2`。
    var dot: CGFloat = 2
    var gap: CGFloat = 1
    /// 軸ラベルのフォント。呼び出し側の文字サイズ設定に合わせて渡す。
    var labelFont: Font = DSTypography.mono(8)
    /// 軸ラベルのフォントサイズ。`labelFont` と同じ値を渡すこと。
    ///
    /// 床（`$0`）のベースラインを格子の下端に合わせるためにディセンダ量が必要で、
    /// `Font` からはサイズを取り出せないため別に受け取る。
    var labelFontSize: CGFloat = 8
    /// 縦軸ラベルの幅。格子の左外にこの幅で右寄せして置く（レイアウト幅は消費しない）。
    ///
    /// 桁数の多い金額が入るので、`$1,234` が縮まずに収まる幅を渡すこと。ただし
    /// **格子とカード端の隙間より広げてはいけない**（幅を消費しない代わりに、
    /// はみ出した分はカードの角丸でクリップされる）。文字サイズ「大」で
    /// `$1,234` のような 6 桁が入ると数 pt 切れることがある。
    var axisWidth: CGFloat = 44

    /// 1 段 / 1 列を構成するブロックの辺（ドット数）。
    private let blockSize = 3
    /// ブロックどうしの空き（ドット数）。
    private let blockSpacing = 1

    private var maxValue: Double { max(values.max() ?? 0, .leastNonzeroMagnitude) }

    /// ドット単位のピッチ。
    private var pitch: CGFloat { dot + gap }

    /// 1 段（= 1 ブロック）の実寸。軸ラベルを行に合わせるために使う。
    private var blockLength: CGFloat {
        CGFloat(blockSize) * dot + CGFloat(blockSize - 1) * gap
    }

    /// 格子の実寸。軸ラベルを列・行に合わせるために使う。
    private var gridWidth: CGFloat {
        let cols = CGFloat(max(1, values.count))
        return cols * blockLength + (cols - 1) * CGFloat(blockSpacing) * pitch
    }

    private var gridHeight: CGFloat {
        let rows = CGFloat(max(1, blocksPerColumn))
        return rows * blockLength + (rows - 1) * CGFloat(blockSpacing) * pitch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 残量は輪郭ブロックが示すので ghost は使わない
            // （ブロック間の空きまで薄く塗ると格子がベタになる）。
            GlyphView(bitmap: bitmap, dot: dot, gap: gap)
            horizontalAxis
        }
        // 縦軸は**幅を消費させず**、格子の左外へオフセットして重ねる。
        //
        // HStack に「ラベル / 格子 / 同じ幅の空き」と並べる手もあるが、
        // 空き側は幅が足りないと縮むので格子がラベル分だけ右へずれる。
        // 固定幅にすればずれないが、こんどはカードの最小幅が膨らんでページの
        // 左右余白を食い潰す。**幅を持たせない**のがどちらの問題も起こさない。
        .overlay(alignment: .topLeading) {
            verticalAxis
                .frame(width: axisWidth, alignment: .trailing)
                .offset(x: -(axisWidth + 6))
        }
        // 格子（固定幅）をカードの中央に置く。
        .frame(maxWidth: .infinity)
        .font(labelFont)
        .foregroundStyle(DSColors.inkMute)
    }

    /// 縦軸。天井（ピーク）と床（0）を段の高さに合わせて置く。
    @ViewBuilder
    private var verticalAxis: some View {
        if let peakLabel {
            // 天井と床は**格子の外縁**に合わせる。段の中心に置くと目盛りが内側に寄って
            // 軸として読めない（「この線から上は無い」「ここが 0」を示すのが軸の役目）。
            VStack(alignment: .trailing, spacing: 0) {
                Text(peakLabel)
                    .frame(height: blockLength, alignment: .top)
                Spacer(minLength: 0)
                Text("$0")
                    .frame(height: blockLength, alignment: .bottom)
                    // `.bottom` はテキストのボックス下端を合わせるので、ディセンダのぶん
                    // 文字が浮く。床の目盛りは**ベースラインが格子の下端**に来るべきなので、
                    // その分だけ押し下げる。
                    .offset(y: Self.descender(for: labelFontSize))
            }
            .frame(height: gridHeight)
            .lineLimit(1)
            // 桁が多いときの保険。ここが頻繁に効くなら axisWidth が足りていない
            // （縮小が常態化すると、指定したフォントサイズが意味を失う）。
            .minimumScaleFactor(0.9)
        }
    }

    /// 横軸。左端・右端の列の真下に置く（チャート幅に揃える）。
    ///
    /// 日付は「いつからいつまでか」の補助なので、金額（天井の値）より一段小さくする。
    /// 同じ大きさだと目盛りが 2 つ同格に並んで、どちらを先に読むのか迷う。
    @ViewBuilder
    private var horizontalAxis: some View {
        if startLabel != nil || endLabel != nil {
            HStack(spacing: 0) {
                Text(startLabel ?? "")
                Spacer(minLength: 0)
                Text(endLabel ?? "")
            }
            .font(DSTypography.mono(max(7, labelFontSize - 2)))
            .frame(width: gridWidth)
        }
    }

    /// テストから点灯の並びを検証できるよう internal に公開している。
    var bitmap: GlyphBitmap {
        let rows = max(1, blocksPerColumn)
        let cols = max(1, values.count)
        let step = blockSize + blockSpacing
        let gridRows = rows * blockSize + (rows - 1) * blockSpacing
        let gridCols = cols * blockSize + (cols - 1) * blockSpacing
        var cells = Array(repeating: Array(repeating: DotCell.off, count: gridCols), count: gridRows)

        for (column, value) in values.enumerated() {
            let lit: Int
            let litColor: Color
            if let loadingPhase {
                lit = Self.waveHeight(column: column, columns: cols, rows: rows, phase: loadingPhase)
                // 値ではないので主張させない。輪郭より一段明るいだけにする。
                litColor = DSColors.inkMute
            } else {
                // 値があるなら最低 1 段は光らせる（微小な日が「無い」ように見えないように）。
                let target = value > 0
                    ? max(1, min(rows, Int(((value / maxValue) * Double(rows)).rounded())))
                    : 0
                lit = Self.revealed(
                    target: target,
                    column: column,
                    columns: cols,
                    progress: revealProgress
                )
                litColor = column == values.count - 1 ? latestColor : color
            }

            for row in 0..<rows {
                let isFilled = row >= rows - lit
                let blockColor = isFilled ? litColor : DSColors.inkGhost
                let originRow = row * step
                let originColumn = column * step

                for y in 0..<blockSize {
                    for x in 0..<blockSize {
                        // 消費済みは塗り（■）、残量は輪郭（□）。グリフ辞書の D と同じ読み方。
                        let isEdge = y == 0 || y == blockSize - 1 || x == 0 || x == blockSize - 1
                        guard isFilled || isEdge else { continue }
                        cells[originRow + y][originColumn + x] = .on(color: blockColor)
                    }
                }
            }
        }
        return GlyphBitmap(rows: gridRows, cols: gridCols, cells: cells)
    }

    /// 立ち上がり途中の段数。列ごとに少し遅らせて（左から順に）目標へ伸ばす。
    static func revealed(target: Int, column: Int, columns: Int, progress: Double) -> Int {
        guard progress < 1 else { return target }
        guard progress > 0 else { return 0 }
        // 列の遅れは全体の 40% ぶんに収める（最後の列も残り 60% の時間で伸びきる）。
        let stagger = 0.4
        let position = Double(column) / Double(max(1, columns - 1))
        let local = (progress - position * stagger) / (1 - stagger)
        guard local > 0 else { return 0 }
        // 終端で少し行き過ぎてから戻る（ゲージの settle と同じ「カチッと止まる」感じ）。
        let eased = min(1.06, easeOutBack(min(1, local)))
        return max(0, min(target, Int((Double(target) * eased).rounded())))
    }

    private static func easeOutBack(_ t: Double) -> Double {
        let overshoot = 1.1
        let p = t - 1
        return 1 + (overshoot + 1) * (p * p * p) + overshoot * (p * p)
    }

    /// フォントのディセンダ量（正の値で返す）。
    static func descender(for fontSize: CGFloat) -> CGFloat {
        -NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).descender
    }

    /// ローディングの波。1 周期を全幅に収め、位相を送ると左から右へ流れる。
    /// 天井まで届かせない（値のチャートと見間違えないよう、高さは段数の半分弱に抑える）。
    static func waveHeight(column: Int, columns: Int, rows: Int, phase: Double) -> Int {
        let position = Double(column) / Double(max(1, columns - 1))
        let wave = (sin((position - phase) * 2 * .pi) + 1) / 2
        return max(0, min(rows, Int((wave * Double(rows) * 0.45).rounded())))
    }
}

#Preview("Usage Block Scale / Chart") {
    VStack(alignment: .leading, spacing: 22) {
        ForEach([12.0, 48.0, 62.0, 88.0, 100.0], id: \.self) { percent in
            HStack(spacing: 12) {
                UsageBlockScale(
                    usedPercent: percent,
                    color: percent >= 90
                        ? DSColors.signalError
                        : (percent >= 70 ? DSColors.signalAlert : DSColors.ink)
                )
                Text("\(Int(percent))%")
                    .font(DSTypography.mono(10, weight: .semibold))
                    .foregroundStyle(DSColors.inkDim)
            }
        }

        Divider().overlay(DSColors.lineDefault)

        UsageBlockChart(
            values: [0.3, 0.5, 0.2, 0.8, 0.45, 0.6, 0.1, 0.9, 0.7, 0.35, 0.55, 1, 0.65, 0.4]
        )
        .frame(width: 360)
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
