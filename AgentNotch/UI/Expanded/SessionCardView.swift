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

/// セッション一覧の 1 行。
///
/// # レイアウト（3 行 + task）
/// ```
/// [dot] repo · branch                    2m [app] [⋯]
///       > fixing auth bug in login flow
///       Edit src/auth.swift ── summary
///       □ Add validation  ■ Fix endpoint  ▪ Write tests
/// ```
///
/// - 行 1: identity (repo · branch) + time + jump icon + menu
/// - 行 2: 目的 (firstUserPrompt、fallback: sessionTitle)
/// - 行 3: 現在の activity (tool + summary、状態に応じて変化)
/// - 行 4: task 一覧 (0 件なら非表示)
struct SessionCardView: View {
    let session: UnifiedSession
    var userState: SessionUserState = .empty
    var isUserDone: Bool = false
    var actions: SessionCardActions = SessionCardActions()

    @Default(.textSize) private var textSize
    @Default(.cardPromptSource) private var promptSource
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Left: DotMatrix + meta labels
            VStack(spacing: 4) {
                DotMatrix(
                    pattern: session.dotPattern,
                    cellSize: 3.2,
                    dotFillRatio: 0.5,
                    animationStartTime: session.doneAt
                )
                .frame(width: 48, height: 48)

                if let model = session.model {
                    Text(shortModel(model))
                        .font(DSTypography.mono(s(7)))
                        .foregroundStyle(DSColors.inkMute)
                        .lineLimit(1)
                }

                Text(session.agentType.displayName.uppercased())
                    .font(DSTypography.mono(s(6), weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(session.agentType.color.opacity(0.5))
            }
            .frame(width: 48)

            // Middle: info rows
            VStack(alignment: .leading, spacing: 3) {
                identityRow
                purposeRow
                activityRow
                subagentRow
                taskRow
            }

            // Right: action column (menu + app icon)
            actionColumn
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0x0C / 255.0, green: 0x13 / 255.0, blue: 0x12 / 255.0))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isUserDone ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { actions.tap() }
    }

    // MARK: - Row 1: Identity

    private let metaFont: CGFloat = 9

    private var identityRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            if userState.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: s(7)))
                    .foregroundStyle(.yellow.opacity(0.7))
                    .rotationEffect(.degrees(45))
            }
            if userState.muted {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: s(7)))
                    .foregroundStyle(DSColors.inkMute)
            }

            if session.teamName != nil {
                Text((session.teammateName ?? "LEAD").uppercased())
                    .font(DSTypography.mono(s(metaFont), weight: .semibold))
                    .foregroundStyle(DSColors.signalThinking.opacity(0.8))
                Text("·")
                    .font(DSTypography.mono(s(metaFont)))
                    .foregroundStyle(DSColors.inkMute)
            }

            Text(repoDisplayName)
                .font(DSTypography.mono(s(10), weight: .medium))
                .foregroundStyle(DSColors.ink)
                .lineLimit(1)

            if let branch = session.gitBranch {
                let isWorktree = session.worktreeName != nil
                Text("·")
                    .font(DSTypography.mono(s(metaFont)))
                    .foregroundStyle(DSColors.inkMute)
                Text(branch)
                    .font(DSTypography.mono(s(metaFont)))
                    .foregroundStyle(isWorktree ? .cyan.opacity(0.5) : DSColors.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(RelativeTimeFormatter.format(since: session.lastActivityAt, relativeTo: context.date))
                    .font(DSTypography.mono(s(metaFont)))
                    .foregroundStyle(DSColors.inkMute)
            }
        }
    }

    // MARK: - Row 2: Purpose

    @ViewBuilder
    private var purposeRow: some View {
        let prompt: String? = switch promptSource {
        case .firstUserMessage: session.firstUserPrompt ?? session.sessionTitle
        case .lastUserMessage: session.lastUserPrompt ?? session.firstUserPrompt ?? session.sessionTitle
        }
        if let prompt, !prompt.isEmpty {
            let flat = prompt.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            HStack(spacing: 4) {
                Text(">")
                    .foregroundStyle(DSColors.inkMute)
                Text(flat)
                    .foregroundStyle(DSColors.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(DSTypography.mono(s(9)))
        }
    }

    // MARK: - Row 3: Activity

    @ViewBuilder
    private var activityRow: some View {
        HStack(spacing: 4) {
            if let tool = session.currentTool, tool.status == .running {
                Text(tool.name)
                    .font(DSTypography.mono(s(9), weight: .medium))
                    .foregroundStyle(session.status.dotPattern.signalColor.opacity(0.9))
                Text(tool.summary)
                    .font(DSTypography.mono(s(9)))
                    .foregroundStyle(DSColors.inkDim)
                    .lineLimit(1)
            } else if session.status == .permissionWaiting {
                if let perm = session.pendingPermissions.first {
                    Text("APPROVE:")
                        .font(DSTypography.mono(s(8), weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(DSColors.signalAlert.opacity(0.9))
                    Text("\(perm.toolName) \(perm.toolInput.values.first ?? "")")
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.inkDim)
                        .lineLimit(1)
                } else if session.pendingQuestion != nil {
                    Text("QUESTION")
                        .font(DSTypography.mono(s(8), weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(DSColors.signalAlert.opacity(0.9))
                }
            } else if session.status == .error {
                Text("ERROR")
                    .font(DSTypography.mono(s(8), weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(DSColors.signalError.opacity(0.9))
            } else if session.status == .done, let msg = session.lastAssistantMessage, !msg.isEmpty {
                Text(msg)
                    .font(DSTypography.mono(s(9)))
                    .foregroundStyle(DSColors.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if session.status != .starting {
                Text(session.status.label.uppercased())
                    .font(DSTypography.mono(s(8), weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(DSColors.inkMute)
            }

            Spacer()
        }
    }

    // MARK: - Row 3.5: Subagents

    @ViewBuilder
    private var subagentRow: some View {
        if !session.subagents.isEmpty {
            SubagentChipsRow(subagents: session.subagents, fontSize: s(8))
        }
    }

    // MARK: - Row 4: Tasks

    @ViewBuilder
    private var taskRow: some View {
        let tasks = session.tasks
        if !tasks.isEmpty {
            HStack(spacing: 8) {
                ForEach(tasks.prefix(6)) { task in
                    HStack(spacing: 3) {
                        Text(task.status.glyph)
                            .foregroundStyle(task.status.color)
                        Text(task.subject)
                            .foregroundStyle(task.status == .completed ? DSColors.inkMute : DSColors.inkDim)
                            .lineLimit(1)
                        if task.status == .inProgress, let assignee = task.assignee {
                            Text("@\(assignee)")
                                .foregroundStyle(DSColors.inkMute)
                        }
                    }
                }
                if tasks.count > 6 {
                    Text("+\(tasks.count - 6)")
                        .foregroundStyle(DSColors.inkMute)
                }
                Spacer()
            }
            .font(DSTypography.mono(s(8)))
        }
    }

    // MARK: - Right action column

    /// 右端に縦積みで ⊙ menu + app icon を配置。
    private var actionColumn: some View {
        VStack(spacing: 4) {
            // ⊙ Menu (ellipsis.circle)
            SessionActionMenu(
                userState: userState,
                isUserDone: isUserDone,
                showTerminalJump: session.pid != nil || session.tty != nil,
                onTogglePin: actions.togglePin,
                onToggleMute: actions.toggleMute,
                onToggleDone: actions.toggleDone,
                onJumpToTerminal: { TerminalJumper.jump(pid: session.pid, tty: session.tty) },
                onRemove: actions.remove,
                labelSize: 14,
                labelFrame: CGSize(width: 28, height: 28),
                symbolName: "ellipsis.circle"
            )

            // App icon (jump target)
            if session.pid != nil || session.tty != nil {
                Button {
                    TerminalJumper.jump(pid: session.pid, tty: session.tty)
                } label: {
                    if let icon = session.terminalAppIcon as? NSImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DSColors.inkMute)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Helpers

    private func shortModel(_ model: String) -> String {
        // "claude-sonnet-4-20250514" → "sonnet-4"
        let parts = model.split(separator: "-")
        if parts.count >= 3, parts.first == "claude" {
            return "\(parts[1])-\(parts[2])"
        }
        return model
    }

    private var repoDisplayName: String {
        session.originRepoName ?? projectName(session.cwd)
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "—" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "—" : name
    }
}

// MARK: - AgentTask.Status display

extension AgentTask.Status {
    /// 工業パネル風グリフ: □ pending / ▪ in_progress / ■ completed
    var glyph: String {
        switch self {
        case .pending: "□"
        case .inProgress: "▪"
        case .completed: "■"
        }
    }

    var color: Color {
        switch self {
        case .pending: DSColors.inkMute
        case .inProgress: DSColors.signalThinking
        case .completed: DSColors.inkDim
        }
    }
}
