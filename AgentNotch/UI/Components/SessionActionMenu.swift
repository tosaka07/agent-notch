import AgentNotchCore
import SwiftUI

/// Shared action menu for a session (Pin / Mute / Mark Done / Terminal jump / Remove).
/// Used by both SessionCardView and SessionDetailView.
struct SessionActionMenu: View {
    let userState: SessionUserState
    let isUserDone: Bool
    /// Whether the agent has supplied a title that can be selected on this card.
    let hasSessionTitle: Bool
    /// Whether to show Terminal jump (true when the session has pid/tty and the caller wants it).
    let showTerminalJump: Bool
    let onTogglePin: () -> Void
    let onToggleMute: () -> Void
    let onToggleDone: () -> Void
    let onSelectTitleDisplayPreference: (SessionTitleDisplayPreference) -> Void
    let onJumpToTerminal: () -> Void
    let onRemove: () -> Void

    /// Font size of the label icon.
    let labelSize: CGFloat
    /// Hit area size of the label icon.
    let labelFrame: CGSize
    /// SF Symbol name used for the label (defaults to "ellipsis").
    let symbolName: String

    init(
        userState: SessionUserState,
        isUserDone: Bool,
        hasSessionTitle: Bool,
        showTerminalJump: Bool = false,
        onTogglePin: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onToggleDone: @escaping () -> Void,
        onSelectTitleDisplayPreference: @escaping (SessionTitleDisplayPreference) -> Void,
        onJumpToTerminal: @escaping () -> Void = {},
        onRemove: @escaping () -> Void,
        labelSize: CGFloat = 10,
        labelFrame: CGSize = CGSize(width: 22, height: 22),
        symbolName: String = "ellipsis"
    ) {
        self.userState = userState
        self.isUserDone = isUserDone
        self.hasSessionTitle = hasSessionTitle
        self.showTerminalJump = showTerminalJump
        self.onTogglePin = onTogglePin
        self.onToggleMute = onToggleMute
        self.onToggleDone = onToggleDone
        self.onSelectTitleDisplayPreference = onSelectTitleDisplayPreference
        self.onJumpToTerminal = onJumpToTerminal
        self.onRemove = onRemove
        self.labelSize = labelSize
        self.labelFrame = labelFrame
        self.symbolName = symbolName
    }

    var body: some View {
        Menu {
            Button(action: onTogglePin) {
                Label(
                    userState.pinned ? L("Unpin") : L("Pin"),
                    systemImage: userState.pinned ? "pin.slash" : "pin"
                )
            }
            Button(action: onToggleMute) {
                Label(
                    userState.muted ? L("Unmute") : L("Mute"),
                    systemImage: userState.muted ? "speaker.wave.2" : "speaker.slash"
                )
            }
            Button(action: onToggleDone) {
                Label(
                    isUserDone ? L("Reopen") : L("Mark Done"),
                    systemImage: isUserDone ? "arrow.uturn.backward" : "checkmark.circle"
                )
            }
            Menu {
                if hasSessionTitle {
                    Button {
                        onSelectTitleDisplayPreference(.sessionTitle)
                    } label: {
                        titleDisplayOption(L("Session title"), preference: .sessionTitle)
                    }
                } else if userState.titleDisplayPreference != .latestPrompt {
                    Text(L("A session title will take priority when it becomes available."))
                        .disabled(true)
                }
                Button {
                    onSelectTitleDisplayPreference(.latestPrompt)
                } label: {
                    titleDisplayOption(L("Latest prompt"), preference: .latestPrompt)
                }
            } label: {
                Label(L("Card title"), systemImage: "textformat")
            }
            if showTerminalJump {
                Divider()
                Button(action: onJumpToTerminal) {
                    Label(L("Jump to Terminal"), systemImage: "arrow.right.square")
                }
            }
            Divider()
            // Removal takes a second, deliberate step. A nested menu is the only
            // confirmation that works here: the panel is nonactivating and cannot
            // become key, so an alert or sheet would not reliably take input.
            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label(L("Confirm — remove this session"), systemImage: "xmark.circle")
                }
            } label: {
                Label(L("Remove from List"), systemImage: "xmark.circle")
            }
        } label: {
            // `.plain` renders the foreground style as specified, so state the white explicitly.
            Image(systemName: symbolName)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(DSColors.ink)
                .frame(width: labelFrame.width, height: labelFrame.height)
                .contentShape(Rectangle())
        }
        // `.borderlessButton` keeps trailing room for the indicator arrow even with
        // `.menuIndicator(.hidden)`. In the list the terminal button sits directly below the ⋯,
        // and inside a trailing-aligned VStack that leftover room shifts the ⋯ left by ~1.5pt,
        // so the two icons no longer share a center. `.button` + `.plain` reserves nothing.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func titleDisplayOption(
        _ title: String,
        preference: SessionTitleDisplayPreference
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selectedTitleDisplayPreference == preference {
                Image(systemName: "checkmark")
            }
        }
    }

    /// A prompt is visible while no agent title exists, but it is not a persistent choice until
    /// the user explicitly selects it. If a title arrives later, the `nil` preference still lets
    /// it become primary.
    private var selectedTitleDisplayPreference: SessionTitleDisplayPreference {
        userState.titleDisplayPreference ?? (hasSessionTitle ? .sessionTitle : .latestPrompt)
    }
}
