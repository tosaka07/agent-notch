import AgentNotchCore
import Defaults
import SwiftUI

struct PermissionBanner: View {
    let permission: PermissionRequest
    var onApprove: () -> Void
    var onDeny: () -> Void
    /// 失効バナー（canRespond=false）を閉じる。
    var onDismiss: () -> Void = {}

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: permission.canRespond
                    ? "exclamationmark.shield.fill" : "clock.badge.exclamationmark.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: s(13)))
                Text(permission.canRespond ? "Permission Required" : "Response window expired")
                    .font(.system(size: s(11), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            // 応答経路が失効した場合は Approve/Deny の代わりにターミナルでの応答を促す
            // （issue #28: 押しても届かないボタンを出さない）。
            if !permission.canRespond {
                Text("This decision can no longer be delivered. Respond directly in the terminal.")
                    .font(.system(size: s(9)))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(permission.toolName)
                    .font(.system(size: s(11), weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))

                ForEach(Array(permission.toolInput.prefix(3)), id: \.key) { key, value in
                    Text("\(key): \(String(value.prefix(80)))")
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 10) {
                if permission.canRespond {
                    Button { onApprove() } label: {
                        Text("Approve")
                            .font(.system(size: s(11), weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 7)
                            .background(Color.green.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button { onDeny() } label: {
                        Text("Deny")
                            .font(.system(size: s(11), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 18).padding(.vertical, 7)
                            .background(Color.red.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { onDismiss() } label: {
                        Text("Dismiss")
                            .font(.system(size: s(11), weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 7)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .armedAfter()
        }
        .padding(14)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }
}
