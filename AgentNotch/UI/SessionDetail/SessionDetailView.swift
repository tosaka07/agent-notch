import AgentNotchCore
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    @ObservedObject var sessionManager: SessionManager
    var onBack: () -> Void

    @State private var chatEntries: [ChatEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 44)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider().overlay(Color.white.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                StatusIndicator(status: session.status, size: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                if let cwd = session.cwd {
                    Text(shortenPath(cwd))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }

                Spacer()

                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 12) {
                if let model = session.model {
                    Text(model).font(.system(size: 9))
                }
                Text("\(TokenFormatter.format(session.totalInputTokens))↓ \(TokenFormatter.format(session.totalOutputTokens))↑")
                    .font(.system(size: 9, design: .monospaced))
                Text(CostCalculator.formatCost(session.estimatedCost))
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.4))
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

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var short = path
        if short.hasPrefix(home) { short = "~" + short.dropFirst(home.count) }
        let parts = short.split(separator: "/")
        if parts.count > 3 { return "~/" + parts.suffix(2).joined(separator: "/") }
        return short
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60; let s = Int(interval) % 60
        return String(format: "%dm %02ds", m, s)
    }
}
