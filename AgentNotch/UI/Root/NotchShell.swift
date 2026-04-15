import SwiftUI

/// Notch 外殻（size / shape clip / glow overlay / shadow / hover / mode animation）を一括適用する ViewModifier。
/// Page 側は「中身」だけに集中できる。
struct NotchShell: ViewModifier {
    let viewModel: NotchViewModel
    let glow: CompletionGlowController

    private var currentShape: NotchShape {
        NotchShape(
            topCornerRadius: viewModel.topCornerRadius,
            bottomCornerRadius: viewModel.bottomCornerRadius
        )
    }

    func body(content: Content) -> some View {
        let isExpanded = viewModel.mode.isFullPanel

        content
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .background(.black)
            .clipShape(currentShape)
            .overlay(
                CompletionFlare(
                    shape: NotchGlowBorder(
                        topCornerRadius: viewModel.topCornerRadius,
                        bottomCornerRadius: viewModel.bottomCornerRadius
                    ),
                    color: glow.color,
                    intensity: glow.intensity
                )
                .clipShape(
                    NotchOuterMask(
                        topCornerRadius: viewModel.topCornerRadius,
                        bottomCornerRadius: viewModel.bottomCornerRadius
                    ),
                    style: FillStyle(eoFill: true)
                )
                .allowsHitTesting(false)
            )
            .shadow(color: isExpanded ? .black.opacity(0.6) : .clear, radius: 8)
            .contentShape(currentShape)
            .onHover { hovering in
                guard viewModel.mode == .compact else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.isHovering = hovering
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: viewModel.mode)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isHovering)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Notch 外殻（size / shape / glow / shadow / hover / mode animation）を適用する。
    func notchShell(viewModel: NotchViewModel, glow: CompletionGlowController) -> some View {
        modifier(NotchShell(viewModel: viewModel, glow: glow))
    }
}
