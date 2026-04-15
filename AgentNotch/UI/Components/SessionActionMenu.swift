import AgentNotchCore
import SwiftUI

/// Session に対する共通アクションメニュー（Pin / Mute / Mark Done / Terminal jump / 一覧から削除）。
/// SessionCardView と SessionDetailView の両方から使う。
struct SessionActionMenu: View {
    let userState: SessionUserState
    let isUserDone: Bool
    /// Terminal jump を表示するか（session.pid/tty があって、呼び出し側が表示したいとき true）
    let showTerminalJump: Bool
    let onTogglePin: () -> Void
    let onToggleMute: () -> Void
    let onToggleDone: () -> Void
    let onJumpToTerminal: () -> Void
    let onRemove: () -> Void

    /// Ellipsis ラベルのフォントサイズ（呼び出し側の textSize スケールに合わせる）
    let labelSize: CGFloat
    /// Ellipsis ラベルのヒットエリアサイズ
    let labelFrame: CGSize

    init(
        userState: SessionUserState,
        isUserDone: Bool,
        showTerminalJump: Bool = false,
        onTogglePin: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onToggleDone: @escaping () -> Void,
        onJumpToTerminal: @escaping () -> Void = {},
        onRemove: @escaping () -> Void,
        labelSize: CGFloat = 10,
        labelFrame: CGSize = CGSize(width: 22, height: 22)
    ) {
        self.userState = userState
        self.isUserDone = isUserDone
        self.showTerminalJump = showTerminalJump
        self.onTogglePin = onTogglePin
        self.onToggleMute = onToggleMute
        self.onToggleDone = onToggleDone
        self.onJumpToTerminal = onJumpToTerminal
        self.onRemove = onRemove
        self.labelSize = labelSize
        self.labelFrame = labelFrame
    }

    var body: some View {
        Menu {
            Button(action: onTogglePin) {
                Label(
                    userState.pinned ? "Pin 解除" : "Pin",
                    systemImage: userState.pinned ? "pin.slash" : "pin"
                )
            }
            Button(action: onToggleMute) {
                Label(
                    userState.muted ? "Mute 解除" : "Mute",
                    systemImage: userState.muted ? "speaker.wave.2" : "speaker.slash"
                )
            }
            Button(action: onToggleDone) {
                Label(
                    isUserDone ? "Reopen" : "Mark Done",
                    systemImage: isUserDone ? "arrow.uturn.backward" : "checkmark.circle"
                )
            }
            if showTerminalJump {
                Divider()
                Button(action: onJumpToTerminal) {
                    Label("ターミナルへ移動", systemImage: "arrow.right.square")
                }
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("一覧から削除", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: labelFrame.width, height: labelFrame.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
