import AgentNotchCore
import Defaults
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    @ObservedObject var sessionManager: SessionManager
    var onBack: () -> Void

    @State private var chatEntries: [ChatEntry] = []
    @State private var isLoading = true
    @State private var isAtBottom = true
    @Default(.textSize) private var textSize
    @Environment(\.permissionActions) private var permissionActions

    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Stats bar
            sessionStatsBar
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)

            // Banners
            if let perm = session.pendingPermissions.first {
                PermissionBanner(
                    permission: perm,
                    onApprove: {
                        permissionActions.approve(session.id, perm.toolUseId)
                    },
                    onDeny: {
                        permissionActions.deny(session.id, perm.toolUseId, "Denied via Agent Notch")
                    }
                )
                .padding(.horizontal, 14).padding(.top, 8)
            }

            if let q = session.pendingQuestion {
                QuestionBanner(question: q.question, options: q.options) { answer in
                    permissionActions.answerQuestion(session.id, q.toolUseId, answer)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }

            chatTabContent
        }
        .onAppear { loadChatAsync() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { onBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: s(10), weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            StatusIndicator(status: session.status, size: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.sessionTitle ?? projectName(session.cwd))
                        .font(.system(size: s(11), weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(session.agentType.displayName)
                        .font(.system(size: s(8), weight: .medium))
                        .foregroundStyle(session.agentType.color.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(session.agentType.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if session.sessionTitle != nil {
                        Text(projectName(session.cwd))
                            .font(.system(size: s(9), design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 4) {
                    if let model = session.model {
                        Text(model)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    if let branch = session.gitBranch {
                        let isWorktree = session.worktreeName != nil
                        if session.model != nil {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.2))
                        }
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: s(7)))
                            .foregroundStyle(isWorktree ? .cyan.opacity(0.5) : .white.opacity(0.3))
                        Text(branch)
                            .foregroundStyle(isWorktree ? .cyan.opacity(0.4) : .white.opacity(0.3))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: s(8), design: .monospaced))
            }

            Spacer()

            if session.pid != nil || session.tty != nil {
                Button {
                    TerminalJumper.jump(pid: session.pid, tty: session.tty)
                } label: {
                    HStack(spacing: 5) {
                        VStack(alignment: .trailing, spacing: 1) {
                            if let name = session.terminalAppName {
                                Text(name)
                                    .font(.system(size: s(8), design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            if let tmux = session.tmuxPaneTarget {
                                Text("tmux:\(tmux)")
                                    .font(.system(size: s(7), design: .monospaced))
                                    .foregroundStyle(.cyan.opacity(0.35))
                            }
                        }
                        if let icon = session.terminalAppIcon as? NSImage {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: s(16), height: s(16))
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: s(10)))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Jump to terminal")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(RelativeTimeFormatter.format(since: session.startedAt, relativeTo: context.date))
                    .font(.system(size: s(9), weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Stats Bar

    private var sessionStatsBar: some View {
        HStack(spacing: 12) {
            statItem(icon: "wrench", value: "\(session.toolCallCount)", label: "tools")
            if session.totalInputTokens > 0 || session.totalOutputTokens > 0 {
                statItem(icon: "arrow.down", value: formatTokens(session.totalInputTokens), label: "in")
                statItem(icon: "arrow.up", value: formatTokens(session.totalOutputTokens), label: "out")
                if session.totalCachedTokens > 0 {
                    statItem(icon: "memorychip", value: formatTokens(session.totalCachedTokens), label: "cached")
                }
            }
            Spacer()
            if session.estimatedCost > 0 {
                Text(String(format: "$%.3f", session.estimatedCost))
                    .font(.system(size: s(9), weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: s(7)))
                .foregroundStyle(.white.opacity(0.3))
            Text(value)
                .font(.system(size: s(9), weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(label)
                .font(.system(size: s(8)))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Chat Tab

    @ViewBuilder
    private var chatTabContent: some View {
        if chatEntries.isEmpty && isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.4))
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)

                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(chatEntries) { entry in
                            ChatMessageView(entry: entry)
                                .id(entry.id)
                        }

                        if let tool = session.currentTool, tool.status == .running {
                            ActiveToolIndicator(tool: tool)
                                .id("activeTool")
                                .transition(.opacity)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .modifier(ScrollBottomTracker(isAtBottom: $isAtBottom))
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: s(10), weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(.white.opacity(0.1))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: isAtBottom)
                .onChange(of: chatEntries.count) { _, _ in
                    if isAtBottom { scrollToBottom(proxy) }
                }
                .onReceive(sessionManager.objectWillChange) {
                    loadChatAsync()
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadChatAsync(then scrollToEnd: Bool = false, proxy: ScrollViewProxy? = nil) {
        guard let path = session.transcriptPath else { return }
        Task { @MainActor in
            let entries = await Task.detached {
                TranscriptReader.read(path: path, tail: 50)
            }.value
            chatEntries = entries
            isLoading = false
            if scrollToEnd, let proxy {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "" }
        return (path as NSString).lastPathComponent
    }
}
