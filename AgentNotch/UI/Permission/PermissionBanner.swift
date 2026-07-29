import AgentNotchCore
import Defaults
import KeyboardShortcuts
import SwiftUI

/// Confirmation banner for a tool-execution permission.
///
/// # Visual approach: continuous with the timeline
/// Built from system controls such as `.borderedProminent`, it would look like
/// **an OS dialog barging into** the black, dot-glyph timeline — hard to trust
/// as part of the panel. It therefore uses the same vocabulary as the rest of
/// the detail view:
/// - The headline is mono uppercase with tracking (no SF Symbols).
/// - The tool payload is the same "black ground + thin border + monospace"
///   block used by `ToolLogRow`.
/// - The decision buttons are `GlyphButton`s, building hierarchy from border
///   and type alone.
///
/// # Placement and hierarchy
/// Pinned to the bottom of the detail view (`SessionDetailView`'s
/// `safeAreaBar`) and presented as **a second surface placed inside the notch
/// panel**. The surface, corner radius, semantic-colored border, and shadow come
/// from `notchCard` — a translucent dark one step lighter than the panel; see
/// `NotchCard`.
///
/// # No glyph in the headline
/// **The status glyph at the top of the panel already shows `!`** for a pending
/// approval. Repeating that glyph inside the card would read as the same state
/// displayed twice. Here the mono uppercase headline and the tool name alone say
/// what the decision is about.
///
/// Return approves and Esc denies (`.defaultAction` / `.cancelAction`).
struct PermissionBanner: View {
    let permission: PermissionRequest
    let keyboardInteraction: KeyboardInteractionController
    var onApprove: () -> Void
    var onDeny: () -> Void
    /// Hands the request back to Codex so its native terminal prompt can answer it.
    var onRespondInTerminal: (() -> Void)?
    /// Dismisses the expired banner (canRespond = false).
    var onDismiss: () -> Void = {}

    @Default(.textSize) private var textSize

    /// The in-flight decision. It drives the progress indicator and prevents a
    /// click plus a hotkey from sending the same response twice.
    @State private var submission = PermissionSubmissionState()

    /// The socket response is synchronous and normally clears the banner in the
    /// same run-loop turn. Keep standard progress feedback visible briefly so
    /// the panel never appears to close on its own.
    private let minimumFeedbackDuration: Duration = .milliseconds(220)

    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// Whether this agent (Codex and friends) has no path for responding from
    /// the notch at all. That means something different from "expired" — a
    /// response that could have been delivered but no longer can — so the
    /// headline, color, and guidance text differ. The approval itself is still
    /// live in the terminal.
    private var isTerminalOnly: Bool {
        !permission.canRespond && permission.agentType != .claudeCode
    }

    /// Semantic color follows whether a response is still possible. Expired
    /// means "can no longer be delivered", which is an error. A terminal-only
    /// agent stays on alert, since the pending approval itself is still live.
    private var accent: Color {
        permission.canRespond || isTerminalOnly ? DSColors.signalAlert : DSColors.signalError
    }

    /// The displayed shortcut is a stable part of the button's identity.
    ///
    /// Approve and deny always show their configurable global hotkeys, whether
    /// or not the panel currently has keyboard focus. Once the panel is engaged,
    /// the command router additionally accepts Return / Escape internally; that
    /// extra convenience must not relabel or resize the buttons.
    private func globalKeyHint(_ shortcut: KeyboardShortcuts.Name) -> ShortcutChord? {
        KeyboardShortcuts.getShortcut(for: shortcut)
            .flatMap { ShortcutChord.fromDisplayDescription($0.description) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            headline

            // The description summarizes what the tool is about to do; putting
            // it in the same black block as the command would make it look like
            // shell output. It goes outside the block, in a non-monospaced
            // face, to read as prose.
            if let summary = permission.toolInput["description"], !summary.isEmpty {
                Text(summary)
                    .font(DSTypography.Native.callout(scale))
                    .foregroundStyle(DSColors.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !permission.canRespond {
                Text(
                    l10n: isTerminalOnly
                        ? "This agent can't be answered from the notch. Respond directly in the terminal."
                        : "This decision can no longer be delivered. Respond directly in the terminal."
                )
                .font(DSTypography.Native.caption(scale))
                .foregroundStyle(DSColors.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            }

            inputBlock

            if permission.agentType == .codex, permission.canRespond {
                Text(l10n: "Allow once or deny here. To change future permissions, answer in the terminal.")
                    .font(DSTypography.Native.caption(scale))
                    .foregroundStyle(DSColors.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DSSpacing.sm) {
                Spacer(minLength: 0)
                if permission.canRespond {
                    if permission.agentType == .codex, onRespondInTerminal != nil {
                        GlyphButton(
                            label: L("Terminal"),
                            shortcut: nil,
                            isEnabled: isAvailable(.terminal),
                            isLoading: submission.decision == .terminal
                        ) { submit(.terminal) }
                        .accessibilityHint(L("Answer this request in the terminal"))
                    }

                    GlyphButton(
                        label: L("Deny").uppercased(),
                        shortcut: globalKeyHint(.denyPermission),
                        isEnabled: isAvailable(.deny),
                        isLoading: submission.decision == .deny
                    ) { submit(.deny) }
                    .accessibilityHint(L("Denies this tool call"))

                    GlyphButton(
                        label: L("Approve").uppercased(),
                        shortcut: globalKeyHint(.approvePermission),
                        tint: DSColors.signalDone,
                        isProminent: true,
                        isEnabled: isAvailable(.approve),
                        isLoading: submission.decision == .approve
                    ) { submit(.approve) }
                    .accessibilityHint(L("Allows \(permission.toolName) to run"))
                } else {
                    GlyphButton(
                        label: L("Dismiss").uppercased(),
                        shortcut: .returnKey,
                        isProminent: true,
                        isEnabled: isAvailable(.dismiss),
                        isLoading: submission.decision == .dismiss
                    ) { submit(.dismiss) }
                    .accessibilityHint(L("Dismisses this expired request"))
                }
            }
            .armedAfter()
        }
        // Tint the surface amber too. The agent is blocked until this is
        // answered, so it should be noticeable from the surface, not just the
        // border.
        .notchCard(accent: accent, tintsSurface: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            permission.canRespond || isTerminalOnly
                ? L("Permission request: \(permission.toolName)")
                : L("Permission request expired: \(permission.toolName)")
        )
        // Global and local keys share one per-panel command stream. Because the
        // stream belongs to one window, all-displays mode cannot submit the same
        // decision more than once.
        .onReceive(keyboardInteraction.commands) { event in
            guard keyboardInteraction.context == .permission else { return }
            switch event.command {
            case .activate:
                submit(permission.canRespond ? .approve : .dismiss)
            case .cancel:
                if permission.canRespond { submit(.deny) }
            case .approve:
                if permission.canRespond { submit(.approve) }
            case .deny:
                if permission.canRespond { submit(.deny) }
            default:
                break
            }
        }
    }

    private func isAvailable(_ decision: PermissionDecision) -> Bool {
        !submission.isSubmitting || submission.decision == decision
    }

    /// Commits the decision after showing standard progress feedback.
    ///
    /// `begin` guards against rapid presses and click/hotkey races. The action
    /// clears the pending request synchronously on success, which removes this
    /// view; on failure it leaves the expired banner in place, so `finish`
    /// restores its Dismiss button.
    private func submit(_ decision: PermissionDecision) {
        guard submission.begin(decision) else { return }
        Task {
            try? await Task.sleep(for: minimumFeedbackDuration)
            switch decision {
            case .approve: onApprove()
            case .deny: onDeny()
            case .terminal: onRespondInTerminal?()
            case .dismiss: onDismiss()
            }
            submission.finish()
        }
    }

    // MARK: - Headline

    /// Mono headline plus tool name. No status glyph — it would duplicate the
    /// one at the top of the panel.
    private var headline: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(
                verbatim: (permission.canRespond || isTerminalOnly
                    ? L("Permission required") : L("Response window expired")).uppercased()
            )
            .font(DSTypography.mono(s(9), weight: .semibold))
            .tracking(1.6)
            // The headline takes the semantic color as well. Surface,
            // border, and headline all point at the same color, so one
            // color states what is happening — red once expired.
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            // The tool name qualifies "what", so it sits one step below the
            // headline's "what is happening". Giving it the semantic color too
            // would flatten them into one level and leave the reading order
            // ambiguous.
            Text(permission.toolName.uppercased())
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(DSColors.inkDim)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    DSShape.rounded(DSShape.badge)
                        .stroke(DSColors.lineDefault, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Tool input

    /// Shows what is being permitted as raw monospaced information, styled like
    /// `ToolLogRow`'s output block.
    ///
    /// Bash appears as `$ command`: reviewing it in the same form you would type
    /// in a terminal makes it easier to recall later what was approved.
    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let command = permission.toolInput["command"], !command.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Text("$")
                        .foregroundStyle(DSColors.inkMute)
                    Text(command)
                        .foregroundStyle(DSColors.ink)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            ForEach(Array(otherInputs.prefix(3)), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 5) {
                    Text(key)
                        .foregroundStyle(DSColors.inkMute)
                    Text(String(value.prefix(120)))
                        .foregroundStyle(DSColors.ink.opacity(0.75))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(DSTypography.mono(s(10)))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // This is a surface inside the card, so it is a material with a scrim
        // rather than flat black — a flat fill would float as the one solid
        // board within the card's texture. A scrim one step darker than the card
        // makes it read as "the recessed surface the values sit on". Push it too
        // dark and the material's blur collapses into a flat fill, so keep the
        // difference slight.
        .background(DSSurfaceFill(.inset))
        .overlay(
            DSShape.rounded(DSShape.inset)
                .stroke(DSColors.lineFaint, lineWidth: 0.5)
        )
        .clipShape(DSShape.rounded(DSShape.inset))
    }

    /// `command` is rendered with a `$` and `description` lives outside the
    /// block, so only the remaining entries are listed here.
    private var otherInputs: [(key: String, value: String)] {
        permission.toolInput
            .filter { $0.key != "command" && $0.key != "description" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
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
        keyboardInteraction: KeyboardInteractionController(),
        onApprove: {},
        onDeny: {}
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}

#Preview("Permission Banner (Expired)") {
    PermissionBanner(
        permission: PermissionRequest(
            id: "2",
            agentType: .claudeCode,
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": "rm -rf build/"],
            toolUseId: "t2",
            timestamp: .now,
            canRespond: false
        ),
        keyboardInteraction: KeyboardInteractionController(),
        onApprove: {},
        onDeny: {},
        onDismiss: {}
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
