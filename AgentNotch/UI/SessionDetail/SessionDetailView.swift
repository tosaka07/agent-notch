import AgentNotchCore
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    @ObservedObject var sessionManager: SessionManager
    var onBack: () -> Void

    @State private var chatEntries: [ChatEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            header
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)

            // Banners
            if let perm = session.pendingPermissions.first {
                PermissionBanner(
                    permission: perm,
                    onApprove: {
                        (NSApp.delegate as? AppDelegate)?.approvePermission(
                            sessionId: session.id, toolUseId: perm.toolUseId)
                    },
                    onDeny: {
                        (NSApp.delegate as? AppDelegate)?.denyPermission(
                            sessionId: session.id, toolUseId: perm.toolUseId,
                            reason: "Denied via Agent Notch")
                    }
                )
                .padding(.horizontal, 14).padding(.top, 8)
            }

            if let q = session.pendingQuestion {
                QuestionBanner(question: q.question, options: q.options) { answer in
                    (NSApp.delegate as? AppDelegate)?.answerQuestion(
                        sessionId: session.id, toolUseId: q.toolUseId, answer: answer)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }

            // Chat log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(chatEntries) { entry in
                            ChatMessageView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    loadChat()
                    scrollToBottom(proxy)
                }
                .onReceive(sessionManager.objectWillChange) {
                    loadChat()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { onBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            StatusIndicator(status: session.status, size: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.agentType.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(projectName(session.cwd))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
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
                            .font(.system(size: 7))
                            .foregroundStyle(isWorktree ? .cyan.opacity(0.5) : .white.opacity(0.3))
                        Text(branch)
                            .foregroundStyle(isWorktree ? .cyan.opacity(0.4) : .white.opacity(0.3))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: 8, design: .monospaced))
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(RelativeTimeFormatter.format(since: session.startedAt, relativeTo: context.date))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func loadChat() {
        guard let path = session.transcriptPath else { return }
        chatEntries = TranscriptReader.read(path: path, tail: 50)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = chatEntries.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func projectName(_ path: String?) -> String {
        guard let path else { return "" }
        return (path as NSString).lastPathComponent
    }
}
