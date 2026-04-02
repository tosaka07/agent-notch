import AgentNotchCore
import SwiftUI

enum NotchMode: Equatable, Sendable {
    case compact
    case expanded
    case sessionDetail(sessionId: String)
}

@MainActor
@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact

    var physicalNotchWidth: CGFloat = 224
    var physicalNotchHeight: CGFloat = 38
    var hasActivity: Bool = false

    var sideWidth: CGFloat {
        max(0, physicalNotchHeight - 12) + 10
    }

    private var expansionWidth: CGFloat {
        hasActivity ? (2 * sideWidth + 20) : 0
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact: physicalNotchWidth + expansionWidth
        case .expanded: 550
        case .sessionDetail: 650
        }
    }

    var notchHeight: CGFloat {
        switch mode {
        case .compact: physicalNotchHeight
        case .expanded: 400
        case .sessionDetail: 550
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact: 6
        case .expanded, .sessionDetail: 12
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .expanded, .sessionDetail: 24
        }
    }

    func toggle() {
        switch mode {
        case .compact: mode = .expanded
        case .expanded: mode = .compact
        case .sessionDetail: mode = .expanded
        }
    }

    func close() { mode = .compact }
    func showSession(_ id: String) { mode = .sessionDetail(sessionId: id) }
    func backToList() { mode = .expanded }
}

struct NotchContentView: View {
    @State var viewModel = NotchViewModel()
    @ObservedObject var sessionManager: SessionManager

    private var animation: Animation {
        viewModel.mode == .compact
            ? .spring(response: 0.45, dampingFraction: 1.0)
            : .spring(response: 0.42, dampingFraction: 0.8)
    }

    var body: some View {
        let hasSessions = !sessionManager.activeSessions.isEmpty

        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: viewModel.topCornerRadius, bottomCornerRadius: viewModel.bottomCornerRadius)
                .fill(.black)
                .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
                .animation(animation, value: viewModel.mode)
                .animation(.smooth, value: viewModel.hasActivity)

            contentForMode
                .animation(animation, value: viewModel.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hasSessions) { _, newValue in
            viewModel.hasActivity = newValue
        }
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch viewModel.mode {
        case .compact:
            compactContent
        case .expanded:
            expandedContent
        case .sessionDetail(let sessionId):
            if let session = sessionManager.session(for: sessionId) {
                SessionDetailView(session: session, sessionManager: sessionManager) {
                    viewModel.backToList()
                }
                .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            } else {
                expandedContent
            }
        }
    }

    // MARK: - Compact

    @ViewBuilder
    private var compactContent: some View {
        let sessions = sessionManager.activeSessions
        if sessions.isEmpty {
            EmptyView()
                .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        } else {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    StatusIndicator(status: sessions.first?.status ?? .idle, size: 10)
                    if sessions.count > 1 {
                        Text("\(sessions.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: viewModel.sideWidth)

                Color.black
                    .frame(width: viewModel.physicalNotchWidth - 6)

                HStack(spacing: 4) {
                    if let tool = sessions.first?.currentTool {
                        Text(tool.summary)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    } else {
                        Text(sessions.first?.status.label ?? "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(width: viewModel.sideWidth)
            }
            .frame(height: viewModel.notchHeight)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Sessions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !sessionManager.activeSessions.isEmpty {
                    Button {
                        sessionManager.removeAllSessions()
                        sessionManager.notifyChange()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 16)

            let sessions = sessionManager.activeSessions
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            SessionCardView(session: session) {
                                viewModel.showSession(session.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
    }
}
