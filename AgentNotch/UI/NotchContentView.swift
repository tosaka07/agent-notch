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

    var physicalNotchWidth: CGFloat
    var physicalNotchHeight: CGFloat
    var hasActivity: Bool = false

    init(notchSize: CGSize = CGSize(width: 224, height: 38)) {
        self.physicalNotchWidth = notchSize.width
        self.physicalNotchHeight = notchSize.height
    }

    /// Extra margin to cover the physical notch's rounded corners
    /// (the API-reported width doesn't account for the corner radii).
    private let notchCornerMargin: CGFloat = 6

    var sideWidth: CGFloat {
        max(0, physicalNotchHeight - 12) + 10
    }

    private var expansionWidth: CGFloat {
        hasActivity ? (2 * sideWidth) : 0
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact: physicalNotchWidth + notchCornerMargin + expansionWidth
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
    @State var viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager

    init(sessionManager: SessionManager, notchSize: CGSize = CGSize(width: 224, height: 38)) {
        self._viewModel = State(initialValue: NotchViewModel(notchSize: notchSize))
        self.sessionManager = sessionManager
    }

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: viewModel.topCornerRadius,
            bottomCornerRadius: viewModel.bottomCornerRadius
        )
    }

    var body: some View {
        let hasSessions = !sessionManager.activeSessions.isEmpty
        let _ = { viewModel.hasActivity = hasSessions }()
        let isOpened = viewModel.mode != .compact

        VStack(spacing: 0) {
            // Notch layout: content + background as one unit, clipped by NotchShape
            VStack(spacing: 0) {
                // Compact header row (always present — persists across open/close)
                compactContent
                    .frame(height: viewModel.physicalNotchHeight)

                // Expanded content (only when opened)
                if isOpened {
                    openedContent
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            )
                        )
                }
            }
            .padding(.horizontal, isOpened ? viewModel.topCornerRadius : 0)
            .padding(.bottom, isOpened ? 12 : 0)
            .frame(
                maxWidth: isOpened ? viewModel.notchWidth : nil,
                maxHeight: isOpened ? viewModel.notchHeight : nil,
                alignment: .top
            )
            .background(.black)
            .clipShape(currentNotchShape)
            .shadow(color: isOpened ? .black.opacity(0.6) : .clear, radius: 6)
            .animation(isOpened ? openAnimation : closeAnimation, value: viewModel.mode)
            .animation(.smooth, value: viewModel.hasActivity)
            .allowsHitTesting(viewModel.mode != .compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hasSessions) { _, newValue in
            viewModel.hasActivity = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentNotchAutoExpand)) { notification in
            if let sessionId = notification.object as? String {
                withAnimation(openAnimation) {
                    viewModel.showSession(sessionId)
                }
            }
        }
    }

    @ViewBuilder
    private var openedContent: some View {
        switch viewModel.mode {
        case .compact:
            EmptyView()
        case .expanded:
            expandedContent
        case .sessionDetail(let sessionId):
            if let session = sessionManager.session(for: sessionId) {
                SessionDetailView(session: session, sessionManager: sessionManager) {
                    viewModel.backToList()
                }
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
        } else {
            let urgentStatus = mostUrgentStatus(sessions)

            HStack(spacing: 0) {
                // Left wing: status indicator
                StatusIndicator(status: urgentStatus, size: 12)
                    .frame(maxWidth: .infinity)

                // Right wing: session count (only if 2+)
                Group {
                    if sessions.count > 1 {
                        Text("\(sessions.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: viewModel.notchHeight)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("Sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                let count = sessionManager.activeSessions.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if !sessionManager.activeSessions.isEmpty {
                    Button {
                        sessionManager.removeAllSessions()
                        sessionManager.notifyChange()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            let sessions = sessionManager.activeSessions
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sessions) { session in
                            SessionCardView(session: session) {
                                viewModel.showSession(session.id)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Returns the most urgent status across all sessions.
    /// Priority: permissionWaiting > error > toolRunning > subagentRunning > thinking > compacting > done > idle
    private func mostUrgentStatus(_ sessions: [UnifiedSession]) -> SessionStatus {
        let priority: [SessionStatus] = [
            .permissionWaiting, .error, .toolRunning, .subagentRunning,
            .thinking, .compacting, .done, .idle, .starting, .completed,
        ]
        for status in priority {
            if sessions.contains(where: { $0.status == status }) {
                return status
            }
        }
        return .idle
    }
}
