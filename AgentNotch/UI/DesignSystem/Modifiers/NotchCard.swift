import SwiftUI

/// notch パネルの中に置く「もう 1 枚の面」。承認 / 質問の割り込みカードが使う。
///
/// # 面の作り方
/// `.regularMaterial` をそのまま敷くと**明るい灰色の板**になり、黒地のパネルから
/// 浮きすぎて OS のダイアログが割り込んだように見える（= アプリの一部として信用しづらい）。
/// モックのカードは `rgba(20,20,22,.94)` 相当の**暗い半透明**なので、material の上に黒を
/// 重ねてから `surface`（white 6%）を薄く乗せ、**パネルより一段だけ明るい面**にする。
///
/// 暗幕の濃さは `DSColors.panelScrimOpacity` / `cardScrimOpacity` で対にして持つ。
/// パネルより薄い暗幕にすることで一段明るい面になり、明度差だけで階層ができる
/// （色味や明るさでは主張させない）。
struct NotchCard: ViewModifier {
    /// 縁に使う意味色（承認待ち = amber、失効 = red）。面には塗らず縁だけ。
    var accent: Color
    var cornerRadius: CGFloat = 16

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
            // 浮いている面であることを影でも示す（明度差だけだと背景と溶ける場面がある）。
            .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            // 透過を切る設定では背後を透かさない。明度差は surface で作る。
            DSColors.surfaceStrong.background(DSColors.canvas)
        } else {
            Rectangle().fill(.regularMaterial)
                .overlay(DSColors.canvas.opacity(DSColors.cardScrimOpacity))
                .overlay(DSColors.surface)
        }
    }
}

extension View {
    /// notch パネルの中に置く暗い半透明のカード面（余白・角丸・意味色の縁・影を一括で適用）。
    func notchCard(accent: Color, cornerRadius: CGFloat = 16) -> some View {
        modifier(NotchCard(accent: accent, cornerRadius: cornerRadius))
    }
}
