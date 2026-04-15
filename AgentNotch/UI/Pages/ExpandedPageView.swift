import AgentNotchCore
import Defaults
import SwiftUI

/// `expanded` モードの UI。アクティブセッション一覧 + 操作バー（clear all / settings）。
struct ExpandedPageView: View {
    let viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: viewModel.physicalNotchHeight + 4)

            HStack(spacing: 6) {
                Text("Sessions")
                    .font(.system(size: s(12), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                let count = sessionManager.activeSessions.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: s(9), weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                if !sessionManager.activeSessions.isEmpty {
                    Button {
                        sessionManager.removeAllSessions()
                        sessionManager.notifyChange()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: s(11)))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: s(11)))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            let sessions = sessionManager.activeSessions
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(size: s(11)))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sessions) { session in
                            SessionCardView(
                                session: session,
                                onTap: {
                                    viewModel.showSession(session.id)
                                },
                                onRemove: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        sessionManager.removeSession(id: session.id)
                                        sessionManager.notifyChange()
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}
