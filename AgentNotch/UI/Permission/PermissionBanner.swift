import AgentNotchCore
import Defaults
import SwiftUI

struct PermissionBanner: View {
    let permission: PermissionRequest
    var onApprove: () -> Void
    var onDeny: () -> Void

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: s(13)))
                Text("Permission Required")
                    .font(.system(size: s(11), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
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
