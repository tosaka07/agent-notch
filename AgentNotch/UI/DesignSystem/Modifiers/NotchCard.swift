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
    /// 縁に使う意味色（承認待ち = amber、失効 = red）。
    var accent: Color
    var cornerRadius: CGFloat = 16
    /// 面もわずかに `accent` に寄せる。
    ///
    /// 「signal 色は面積に使わない」原則の例外。承認は**押すまで agent が止まっている**
    /// 唯一の状態なので、縁だけでなく面で気づけるようにする。同時に複数出ることは
    /// ないので、画面が意味色で溢れる心配もない。
    var tintsSurface: Bool = false

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
            DSColors.surfaceStrong
                .background(DSColors.canvas)
                .overlay(tintsSurface ? accent.opacity(0.12) : .clear)
        } else {
            Rectangle().fill(.regularMaterial)
                .overlay(DSColors.canvas.opacity(DSColors.cardScrimOpacity))
                .overlay(DSColors.surface)
                .overlay(tintsSurface ? accent.opacity(0.12) : .clear)
        }
    }
}

extension View {
    /// notch パネルの中に置く暗い半透明のカード面（余白・角丸・意味色の縁・影を一括で適用）。
    /// `tintsSurface` を立てると面もわずかに `accent` に寄る（承認のように面で気づかせたいとき）。
    func notchCard(
        accent: Color,
        cornerRadius: CGFloat = 16,
        tintsSurface: Bool = false
    ) -> some View {
        modifier(NotchCard(accent: accent, cornerRadius: cornerRadius, tintsSurface: tintsSurface))
    }
}
