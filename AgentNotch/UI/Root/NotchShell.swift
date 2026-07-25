import Defaults
import SwiftUI

/// Notch 外殻（size / shape clip / glow overlay / shadow / hover / mode animation）を一括適用する ViewModifier。
/// Page 側は「中身」だけに集中できる。
struct NotchShell: ViewModifier {
    let viewModel: NotchViewModel
    let glow: CompletionGlowController

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Default(.panelSurfaceStyle) private var panelSurfaceStyle

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
    ///
    /// **material の View は出し入れせず、手前の黒の不透明度だけを変える**。
    /// `if isExpanded` で material 自体を差し替えると、閉じる瞬間に material が
    /// 角丸クリップ前の矩形のまま 1 フレーム残り、compact の角が四角く見える。
    /// 常設して不透明度を補間すれば、展開パネルの色から compact の黒へ滑らかに溶ける。
    ///
    /// # 暗幕の 3 モード（`Defaults[.panelSurfaceStyle]`）
    /// - `.solid`: パネル全体を同じ濃さの黒で覆う（従来）
    /// - `.gradient`: 上端は不透明な黒のまま、**下端で material に移行**する
    /// - `.liquidGlass`: 面を macOS 26 の `glassEffect` で作り、下端は暗幕を完全に外す
    ///
    /// どのモードでも**面（material / glass）の View は出し入れせず、手前の黒の濃さだけ**を
    /// 変える。`if` で面を差し替えると、閉じる瞬間に角丸クリップ前の矩形が 1 フレーム残り、
    /// compact の角が四角く見える。グラデーションも固定で置き、compact 用の不透明黒を
    /// opacity で被せて切り替える（`LinearGradient` は補間できないため）。
    private func panelBackground(isExpanded: Bool) -> some View {
        let translucent = isExpanded && !reduceTransparency
        return panelSurface
            .overlay {
                switch panelSurfaceStyle {
                case .solid:
                    // compact では黒を不透明にして面を完全に覆う（= notch と地続きの黒）。
                    Color.black.opacity(translucent ? DSColors.panelScrimOpacity : 1)
                case .gradient, .liquidGlass:
                    LinearGradient(
                        gradient: panelSurfaceStyle == .liquidGlass
                            ? DSColors.panelGlassScrimGradient
                            : DSColors.panelScrimGradient,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(Color.black.opacity(translucent ? 0 : 1))
                }
            }
            .overlay(alignment: .bottom) {
                // すりガラス（material の近似）にだけ下端の光沢を足す。
                // Liquid Glass は屈折と明暗を自前で持つので、重ねると濁る。
                if panelSurfaceStyle == .gradient {
                    LinearGradient(
                        gradient: DSColors.glassEdgeHighlight,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 52)
                    .opacity(translucent ? 1 : 0)
                    .allowsHitTesting(false)
                }
            }
    }

    /// ガラスの縁。
    ///
    /// **背後を拾う material のストローク + 下ほど強くなる白のハイライト**の二層で作る。
    /// 単色 1px だと「線を引いた板」に見えるが、実際のガラスは屈折した背景が縁で
    /// 明るくなることで輪郭が立つ。material 側が背景の色を拾うので、暗い壁紙の上では
    /// 縁も暗く、明るい壁紙の上では明るくなる。
    ///
    /// 上端（物理 notch との接地部）は縁を出さない。境目に線が入ると notch から浮く。
    private func glassEdge(translucent: Bool) -> some View {
        currentShape
            .stroke(.ultraThinMaterial, lineWidth: 1)
            .overlay {
                currentShape.stroke(
                    LinearGradient(
                        gradient: DSColors.glassEdgeStroke,
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .mask(
                LinearGradient(
                    gradient: DSColors.glassEdgeMask,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(translucent ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// パネルの面そのもの。`liquidGlass` だけ macOS 26 の Liquid Glass を使う。
    @ViewBuilder
    private var panelSurface: some View {
        if panelSurfaceStyle == .liquidGlass, !reduceTransparency {
            // `.clear` は Liquid Glass の中でもっとも背景を通すバリアント。
            // 暗い UI なので黒を tint して、ガラス自体の明るさを抑える。
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear.tint(.black.opacity(0.25)), in: Rectangle())
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    /// モード遷移のアニメーション。
    ///
    /// 開くときはバネの伸び（わずかなオーバーシュート）が気持ちよいが、**閉じるときは
    /// オーバーシュートさせない**。compact サイズを一瞬下回ると、物理 notch の縁から
    /// 背後が覗いてパネルが「ぐっと縮んで戻る」ように見えるため、臨界制動で着地させる。
    private var modeAnimation: Animation {
        viewModel.mode.isFullPanel
            ? .spring(response: 0.42, dampingFraction: 0.85)
            : .spring(response: 0.34, dampingFraction: 1)
    }

    func body(content: Content) -> some View {
        let isExpanded = viewModel.mode.isFullPanel

        content
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .background(panelBackground(isExpanded: isExpanded))
            .clipShape(currentShape)
            .overlay {
                // 縁は clip の外側に描く（clip 内だと線幅の半分が削られて掠れる）。
                if panelSurfaceStyle == .liquidGlass, !reduceTransparency {
                    glassEdge(translucent: isExpanded)
                }
            }
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
            // 影も opacity で補間する（`.clear` との差し替えだと閉じ際に影が飛んで見える）。
            .shadow(color: .black.opacity(isExpanded ? 0.6 : 0), radius: 8)
            .contentShape(currentShape)
            .onHover { hovering in
                guard viewModel.mode == .compact else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.isHovering = hovering
                }
            }
            .animation(modeAnimation, value: viewModel.mode)
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
