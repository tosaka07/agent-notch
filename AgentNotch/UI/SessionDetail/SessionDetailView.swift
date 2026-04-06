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
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 0.5)

            // Permission / Question banners
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
                .padding(.horizontal, 10).padding(.top, 6)
            }

            if let q = session.pendingQuestion {
                QuestionBanner(question: q.question, options: q.options) { answer in
                    (NSApp.delegate as? AppDelegate)?.answerQuestion(
                        sessionId: session.id, toolUseId: q.toolUseId, answer: answer)
                }
                .padding(.horizontal, 10).padding(.top, 6)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            StatusIndicator(status: session.status, size: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.agentType.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(projectName(session.cwd))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                        .lineLimit(1)
                }
                if let model = session.model {
                    Text(model)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            Spacer()

            Text(formatDuration(session.elapsedTime))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
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

    private func formatDuration(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60; let s = Int(interval) % 60
        return String(format: "%d:%02d", m, s)
    }
}
