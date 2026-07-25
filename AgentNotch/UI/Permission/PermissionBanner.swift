import AgentNotchCore
import Defaults
import SwiftUI

/// tool 実行の許可確認バナー。ネイティブなダイアログ的振る舞い（HIG）:
/// - `.borderedProminent` / `.bordered(role: .destructive)` の標準コントロール
/// - Return で Approve、Esc で Deny（`.defaultAction` / `.cancelAction`）
/// - `.regularMaterial` によるパネル背景 + signal color は縁取りのみ（面を塗らない）
struct PermissionBanner: View {
    let permission: PermissionRequest
    var onApprove: () -> Void
    var onDeny: () -> Void

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var scale: CGFloat { textSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(DSColors.signalAlert)
                    .font(DSTypography.Native.callout(scale))
                Text("Permission Required")
                    .font(DSTypography.Native.headline(scale))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(permission.toolName)
                    .font(DSTypography.Native.monoCallout(scale, weight: .medium))
                    .foregroundStyle(.primary)

                ForEach(Array(permission.toolInput.prefix(3)), id: \.key) { key, value in
                    Text("\(key): \(String(value.prefix(80)))")
                        .font(DSTypography.Native.monoCaption(scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(reduceTransparency ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.regularMaterial))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: DSSpacing.sm) {
                Button(role: .destructive) {
                    onDeny()
                } label: {
                    Text("Deny")
                        .font(DSTypography.Native.callout(scale, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("この tool 実行を拒否します")

                Button {
                    onApprove()
                } label: {
                    Text("Approve")
                        .font(DSTypography.Native.callout(scale, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(DSColors.signalDone)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("\(permission.toolName) の実行を許可します")
            }
            .armedAfter()
        }
        .padding(DSSpacing.md)
        .background(reduceTransparency ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DSColors.signalAlert.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("権限リクエスト: \(permission.toolName)")
        // Approve/Deny の Return/Esc ショートカットはパネルが key window の間だけ効く
        // （NotchPanel は既定 canBecomeKey=false）。表示中だけ許可し、消えたら戻す（#2 と同様の経路）。
        .onAppear {
            NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: false)
        }
    }
}

#Preview("Permission Banner") {
    PermissionBanner(
        permission: PermissionRequest(
            id: "1",
            agentType: .claudeCode,
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": "rm -rf build/", "description": "Clean build artifacts"],
            toolUseId: "t1",
            timestamp: .now,
            canRespond: true
        ),
        onApprove: {},
        onDeny: {}
    )
    .padding(24)
    .frame(width: 360)
    .background(Color.black)
}
