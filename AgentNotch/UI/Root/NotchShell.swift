import SwiftUI

/// Notch 外殻（size / shape clip / glow overlay / shadow / hover / mode animation）を一括適用する ViewModifier。
/// Page 側は「中身」だけに集中できる。
struct NotchShell: ViewModifier {
    let viewModel: NotchViewModel
    let glow: CompletionGlowController

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var currentShape: NotchShape {
        NotchShape(
            topCornerRadius: viewModel.topCornerRadius,
            bottomCornerRadius: viewModel.bottomCornerRadius
        )
    }

    /// パネルの背景。
    ///
    /// compact / notification は notch の延長なので**不透明な黒**（物理 notch と地続きに見せる）。
    /// 展開パネルは Apple の material を借りて半透明 + ブラーにする（モック 1b/1d の
    /// `rgba(20,20,22,.94)` + `backdrop-filter: blur(34px) saturate(160%)` に相当）。
    /// ドットの視認性を保つため黒を強めに重ね、Reduce Transparency 時は不透明に落とす。
    @ViewBuilder
    private func panelBackground(isExpanded: Bool) -> some View {
        if isExpanded, !reduceTransparency {
            Color.black.opacity(0.82).background(.ultraThinMaterial)
        } else {
            Color.black
        }
    }

    func body(content: Content) -> some View {
        let isExpanded = viewModel.mode.isFullPanel

        content
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .background(panelBackground(isExpanded: isExpanded))
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
            .overlay(alignment: .topTrailing) {
                // 選択画面（expanded / sessionDetail）表示中に裏で別セッションが完了すると
                // outline は光るがどのセッションか分からないため、repo 名を短時間表示する（#3）。
                if isExpanded, let label = glow.label {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(glow.color.opacity(0.28))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(glow.color.opacity(0.55), lineWidth: 1))
                        .padding(8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
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
