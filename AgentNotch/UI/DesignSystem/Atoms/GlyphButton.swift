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
    var action: () -> Void

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var labelColor: Color {
        guard isEnabled else { return DSColors.inkMute }
        return isProminent ? tint : DSColors.inkDim
    }

    private var borderColor: Color {
        guard isEnabled else { return DSColors.lineFaint }
        return isProminent ? tint.opacity(0.5) : DSColors.lineStrong
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(DSTypography.mono(s(10), weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(labelColor)
                if let shortcut {
                    Text(shortcut)
                        .font(DSTypography.mono(s(8)))
                        .foregroundStyle(isEnabled ? DSColors.inkMute : DSColors.lineStrong)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(isProminent && isEnabled ? tint.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
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
