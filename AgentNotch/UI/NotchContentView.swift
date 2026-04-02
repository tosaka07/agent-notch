import SwiftUI

enum NotchMode: Sendable {
    case compact
    case expanded
    case fullPanel
}

@MainActor
@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact

    var notchWidth: CGFloat {
        switch mode {
        case .compact: 224
        case .expanded: 550
        case .fullPanel: 650
        }
    }

    var notchHeight: CGFloat {
        switch mode {
        case .compact: 38
        case .expanded: 400
        case .fullPanel: 500
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact: 6
        case .expanded, .fullPanel: 19
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .expanded, .fullPanel: 24
        }
    }

    func toggle() {
        switch mode {
        case .compact:
            mode = .expanded
        case .expanded:
            mode = .fullPanel
        case .fullPanel:
            mode = .compact
        }
    }

    func close() {
        mode = .compact
    }
}

struct NotchContentView: View {
    @State var viewModel = NotchViewModel()

    private let animation: Animation = .spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(
                topCornerRadius: viewModel.topCornerRadius,
                bottomCornerRadius: viewModel.bottomCornerRadius
            )
            .fill(.black)
            .frame(
                width: viewModel.notchWidth,
                height: viewModel.notchHeight
            )
            .animation(animation, value: viewModel.mode)

            contentForMode
                .animation(animation, value: viewModel.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch viewModel.mode {
        case .compact:
            Text("Agent Notch")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)

        case .expanded:
            VStack(spacing: 12) {
                Text("Sessions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 44)

                Spacer()

                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()
            }
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)

        case .fullPanel:
            VStack(spacing: 12) {
                Text("Agent Notch")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 44)

                Spacer()

                Text("Full Panel Mode")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()
            }
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
        }
    }
}
