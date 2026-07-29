import Defaults
import SwiftUI

/// Shared row layout for session notifications (completion / sweep):
/// icon + title + project name + git branch + marquee message.
struct SessionNotificationContent: View {
    let icon: AnyView
    let sessionTitle: String?
    let projectName: String
    let gitBranch: String?
    let isWorktree: Bool
    let message: String
    let onMarqueeComplete: () -> Void

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    init(
        icon: AnyView,
        sessionTitle: String? = nil,
        projectName: String,
        gitBranch: String?,
        isWorktree: Bool = false,
        message: String,
        onMarqueeComplete: @escaping () -> Void = {}
    ) {
        self.icon = icon
        self.sessionTitle = sessionTitle
        self.projectName = projectName
        self.gitBranch = gitBranch
        self.isWorktree = isWorktree
        self.message = message
        self.onMarqueeComplete = onMarqueeComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                icon.font(.system(size: s(9)))
                if let title = sessionTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: s(9), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text(projectName)
                    .font(
                        .system(
                            size: s(9), weight: sessionTitle == nil ? .semibold : .regular,
                            design: .monospaced)
                    )
                    .foregroundStyle(.white.opacity(sessionTitle == nil ? 0.7 : 0.45))
                if let branch = gitBranch {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: s(7)))
                        .foregroundStyle(isWorktree ? .cyan.opacity(0.5) : .white.opacity(0.3))
                    Text(branch)
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundStyle(isWorktree ? .cyan.opacity(0.4) : .white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
            }

            if !message.isEmpty {
                MarqueeText(
                    text: message,
                    font: .system(size: s(10), weight: .medium),
                    onCycleComplete: onMarqueeComplete
                )
                .foregroundStyle(.white.opacity(0.55))
                .frame(height: s(14))
            }
        }
    }
}
