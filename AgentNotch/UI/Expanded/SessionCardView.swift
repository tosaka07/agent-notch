import AgentNotchCore
import Defaults
import SwiftUI

/// SessionCardView の 5 種のコールバックを集約。初期値は全て no-op。
struct SessionCardActions {
    var tap: () -> Void = {}
    var remove: () -> Void = {}
    var togglePin: () -> Void = {}
    var toggleMute: () -> Void = {}
    var toggleDone: () -> Void = {}
}

struct SessionCardView: View {
    let session: UnifiedSession
    var userState: SessionUserState = .empty
    var isUserDone: Bool = false
    var actions: SessionCardActions = SessionCardActions()

    @Default(.textSize) private var textSize

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: Pin + Status + Title ... Mute + Duration + ⋯ Menu
            HStack(spacing: 6) {
                if userState.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: s(8), weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.7))
                        .rotationEffect(.degrees(45))
                }
                StatusIndicator(status: session.status, size: 7)
                if userState.muted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: s(8)))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text(sessionDisplayName)
                    .font(.system(size: s(11), weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(RelativeTimeFormatter.format(since: session.startedAt, relativeTo: context.date))
                        .font(.system(size: s(9), weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                actionMenu
            }

            // Row 2: Model · Project · Branch ... Agent badge
            HStack(spacing: 0) {
                if let model = session.model {
                    Text(shortModel(model))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(" · ")
                        .foregroundStyle(.white.opacity(0.2))
                }
                if let repoName = session.originRepoName {
                    Text(repoName)
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    Text(projectName(session.cwd))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let branch = session.gitBranch {
                    let isWorktree = session.worktreeName != nil
                    Text(" · ")
                        .foregroundStyle(.white.opacity(0.2))
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: s(7)))
                        .foregroundStyle(isWorktree ? .cyan.opacity(0.5) : .white.opacity(0.3))
                    Text(branch)
                        .foregroundStyle(isWorktree ? .cyan.opacity(0.4) : .white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Text(session.agentType.displayName)
                    .font(.system(size: s(8), weight: .medium))
                    .foregroundStyle(session.agentType.color.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(session.agentType.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .font(.system(size: s(9), design: .monospaced))

            // Row 3: Tool activity ... Terminal jump
            HStack(spacing: 4) {
                if let tool = session.currentTool, tool.status == .running {
                    PulsingDot(color: session.status.color, size: 4)
                    Text(tool.name)
                        .font(.system(size: s(9), weight: .medium, design: .monospaced))
                        .foregroundStyle(session.status.color.opacity(0.9))
                    Text(tool.summary)
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                } else {
                    Text(session.status.label)
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                if session.pid != nil || session.tty != nil {
                    Button {
                        TerminalJumper.jump(pid: session.pid, tty: session.tty)
                    } label: {
                        HStack(spacing: 3) {
                            if let icon = session.terminalAppIcon as? NSImage {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: s(12), height: s(12))
                            }
                            if let name = session.terminalAppName {
                                Text(name)
                                    .font(.system(size: s(8), design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            if let tmux = session.tmuxPaneTarget {
                                Text("tmux:\(tmux)")
                                    .font(.system(size: s(7), design: .monospaced))
                                    .foregroundStyle(.cyan.opacity(0.35))
                            }
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: s(8)))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: s(14))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    cardBorderColor,
                    lineWidth: session.status == .done ? 1 : 0.5
                )
        )
        .opacity(isUserDone ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { actions.tap() }
    }

    // MARK: - Action menu

    private var actionMenu: some View {
        SessionActionMenu(
            userState: userState,
            isUserDone: isUserDone,
            showTerminalJump: session.pid != nil || session.tty != nil,
            onTogglePin: actions.togglePin,
            onToggleMute: actions.toggleMute,
            onToggleDone: actions.toggleDone,
            onJumpToTerminal: { TerminalJumper.jump(pid: session.pid, tty: session.tty) },
            onRemove: actions.remove,
            labelSize: s(9),
            labelFrame: CGSize(width: 18, height: 16)
        )
    }

    private var cardBorderColor: Color {
        switch session.status {
        case .permissionWaiting:
            session.status.color.opacity(0.5)
        case .done:
            Color.green.opacity(0.4)
        default:
            Color.white.opacity(0.06)
        }
    }

    private func shortModel(_ model: String) -> String {
        let parts = model.split(separator: "-")
        if parts.count >= 3, parts.first == "claude" {
            return "\(parts[1])-\(parts[2])"
        }
        return model
    }

    /// Display name: customTitle > slug > project directory
    private var sessionDisplayName: String {
        if let title = session.sessionTitle, !title.isEmpty { return title }
        return projectName(session.cwd)
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "—" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "—" : name
    }
}
