import AgentNotchCore
import Defaults
import SwiftUI

struct SessionCardView: View {
    let session: UnifiedSession
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    @Default(.textSize) private var textSize

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Status + Agent name + Duration
            HStack(spacing: 6) {
                StatusIndicator(status: session.status, size: 7)
                Text(session.agentType.displayName)
                    .font(.system(size: s(11), weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(RelativeTimeFormatter.format(since: session.startedAt, relativeTo: context.date))
                        .font(.system(size: s(9), weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: s(7), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            // Row 2: Model + Project name + Branch
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
            }
            .font(.system(size: s(9), design: .monospaced))
            .padding(.bottom, 6)

            // Row 3: Tool activity — fixed height
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
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: s(9)))
                            .foregroundStyle(.white.opacity(0.3))
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
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
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

    private func projectName(_ path: String?) -> String {
        guard let path else { return "—" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "—" : name
    }
}
