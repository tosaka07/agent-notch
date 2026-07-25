import SwiftUI

/// 横長のピクセル調プログレスバー。`usedPercent` に応じてセルを左から塗りつぶす。
///
/// USAGE セクションの各ウィンドウ（session / week 等）の使用率表示に使う。
/// 色は使用率に応じて自動でエスカレーションする（通常 → 警戒 → 危険）。
struct UsageBar: View {
    /// 0〜100 の使用率。
    let usedPercent: Double
    var dotCount: Int = 28
    var dotSize: CGFloat = 3
    var spacing: CGFloat = 2
    var ghostColor: Color = DSColors.inkGhost

    private var clampedPercent: Double { min(max(usedPercent, 0), 100) }

    private var filledCount: Int {
        Int((clampedPercent / 100 * Double(dotCount)).rounded())
    }

    private var fillColor: Color {
        switch clampedPercent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: DSColors.ink
        }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Rectangle()
                    .fill(index < filledCount ? fillColor : ghostColor)
                    .frame(width: dotSize, height: dotSize)
            }
        }
    }
}
