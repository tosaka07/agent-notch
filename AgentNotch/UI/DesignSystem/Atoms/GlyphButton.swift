import Defaults
import SwiftUI

/// パネル内の決定ボタン（承認 / 拒否 / 送信）。
///
/// `.borderedProminent` などの system control は、黒地 + ドットグリフのパネルに置くと
/// **OS のダイアログが挟まったように浮いて見える**。タイムラインやカードと同じ
/// 「黒地・細い枠・mono 大文字」で組み、パネルの一部として地続きに見せる。
///
/// # 階層
/// - `isProminent`: 主たる決定（APPROVE / SEND）。`tint` の薄い塗り + 明るい枠
/// - それ以外: 副の決定（DENY / DISMISS）。枠のみ
///
/// signal 色は「面積に使わない」原則があるため、塗りは 12% までに抑えて縁と文字で語らせる。
struct GlyphButton: View {
    let label: String
    /// `⏎` / `esc` のようなキーヒント。押せる操作が形で分かると誤操作が減る。
    var shortcut: String?
    /// 主色。枠・文字・薄塗りに使う。
    var tint: Color = DSColors.ink
    var isProminent: Bool = false
    var isEnabled: Bool = true
    /// 押された直後の演出。true の間、面が `tint` で満ちて文字が反転する。
    ///
    /// ホットキーで押されたときも「どちらを押したか」が見えるようにするため、
    /// 押下状態はボタン自身の `@State` ではなく**呼び出し側から与える**。
    var isFlashing: Bool = false
    var action: () -> Void

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var labelColor: Color {
        if isFlashing { return .black }
        guard isEnabled else { return DSColors.inkMute }
        return isProminent ? tint : DSColors.inkDim
    }

    private var borderColor: Color {
        if isFlashing { return tint }
        guard isEnabled else { return DSColors.lineFaint }
        return isProminent ? tint.opacity(0.5) : DSColors.lineStrong
    }

    private var fillColor: Color {
        if isFlashing { return tint }
        return isProminent && isEnabled ? tint.opacity(0.12) : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(DSTypography.mono(s(10), weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(labelColor)
                if let shortcut {
                    // ラベルより 1pt 大きい。⌥⇧⏎ のような記号は同じ pt でも字面が小さく
                    // 見えるので、光学的に釣り合わせるにはこちらを上げる必要がある。
                    // 階層は色（inkDim）と字間で付ける。
                    Text(shortcut)
                        .font(DSTypography.mono(s(11)))
                        // 修飾キーの記号は字面が似ていて、詰まっていると 1 つの図形に
                        // 見える（⌥⇧⏎ が判別できない）。字間を空けて 1 キーずつ読ませる。
                        .tracking(2)
                        .foregroundStyle(
                            isFlashing
                                ? .black.opacity(0.55)
                                : (isEnabled ? DSColors.inkDim : DSColors.lineStrong)
                        )
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            // 面が満ちるのと同時にわずかに沈ませる（押した手応え）。
            .scaleEffect(isFlashing ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isFlashing)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

#Preview("Glyph Buttons") {
    HStack(spacing: 10) {
        GlyphButton(label: "DENY", shortcut: "esc", action: {})
        GlyphButton(
            label: "APPROVE",
            shortcut: "⏎",
            tint: DSColors.signalDone,
            isProminent: true,
            action: {}
        )
        GlyphButton(label: "SEND", tint: DSColors.signalAlert, isProminent: true, isEnabled: false, action: {})
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
