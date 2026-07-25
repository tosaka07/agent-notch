import SwiftUI

/// Agent Notch デザインシステムのカラートークン。
///
/// # 使い分けルール
/// - 面積ベースの背景色に `signal.*` は使わない（dot / underbar / glow / 1 文字 badge のみ）
/// - 2 色同時発色は許容、3 色は禁止
/// - 色は状態の補助。色が消えても DotPattern の形で状態が読めること
enum DSColors {
    // MARK: - Base

    static let canvas = Color.black
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.10)

    // MARK: - Scrim（material の上に重ねる暗幕）
    //
    // 展開パネルとその中のカードは material（ブラー）の上に黒を重ねて作る。
    // 黒を濃くしすぎると material の質感が消えて「ただの黒い板」になり、
    // 薄すぎるとドットや細い罫線が背景に負ける。**パネルとカードの差**で階層を作るので、
    // 2 つの値は必ずセットで調整すること。

    /// 展開パネルの暗幕。
    static let panelScrimOpacity: Double = 0.72
    /// パネルの中に置くカードの暗幕。パネルより薄くして一段明るい面にする。
    static let cardScrimOpacity: Double = 0.56

    /// 黒の暗幕を滑らかに抜くグラデーションを組む。
    ///
    /// 少数の stop（4〜5 点）で書くと、**変化率が切り替わる位置が「線」として見える**。
    /// 目は明るさそのものより明るさの変化率の不連続に敏感なので、`smoothstep`
    /// （両端で傾きが 0 になる 3t²−2t³）を細かく刻んだ多数の stop で近似する。
    ///
    /// - Parameters:
    ///   - fadeStart: 抜き始める位置（ここまでは `top` の濃さを保つ）
    ///   - top: 上端の黒の濃さ。物理 notch と地続きにするため既定は完全な黒
    ///   - bottom: 下端の黒の濃さ
    private static func smoothScrim(
        color: Color = .black,
        fadeStart: Double,
        top: Double = 1,
        bottom: Double,
        steps: Int = 16
    ) -> Gradient {
        var stops: [Gradient.Stop] = [.init(color: color.opacity(top), location: 0)]
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            stops.append(
                .init(
                    color: color.opacity(top + (bottom - top) * eased),
                    location: fadeStart + (1 - fadeStart) * t
                )
            )
        }
        return Gradient(stops: stops)
    }

    /// `PanelSurfaceStyle.gradient` の暗幕。
    ///
    /// **上端は完全な黒**（物理 notch と地続きでなければならない）。抜けるのは**下 3 割だけ**。
    /// 上まで抜くと全体が「灰色の板」になり、ドットや細い罫線が背景に負けて読みにくくなる。
    static let panelScrimGradient = smoothScrim(fadeStart: 0.7, bottom: 0.22)

    /// `PanelSurfaceStyle.liquidGlass` の暗幕。
    ///
    /// 面が本物のガラス（`glassEffect`）なので、`gradient` より抜けを大きく取り、
    /// **下端は暗幕を完全に外して素のガラスを見せる**。material の近似では下端まで
    /// 黒を残さないと「白っぽい板」に見えてしまうが、Liquid Glass は自前で
    /// 屈折と明暗を持つのでその必要がない。
    static let panelGlassScrimGradient = smoothScrim(fadeStart: 0.7, bottom: 0)

    /// Liquid Glass の縁に重ねるハイライト。
    ///
    /// 単色の 1px ストロークだと「線を引いた板」に見える。実際のガラスの輪郭は
    /// **屈折した背景が縁で明るくなる**ことで立つので、下（ガラスが露出する側）へ向かって
    /// 強くなる白を、背景を拾う material のストロークと二層で重ねる。
    static let glassEdgeStroke = smoothScrim(
        color: .white,
        fadeStart: 0,
        top: 0.04,
        bottom: 0.28
    )

    /// ガラスの縁をどこから見せるかのマスク。
    /// 上端は物理 notch と地続きなので縁を出さない（境目に線が入ると浮いて見える）。
    /// 暗幕が抜け始めるより少し手前から出して、縁が急に現れないようにする。
    static let glassEdgeMask = smoothScrim(
        color: .white,
        fadeStart: 0.5,
        top: 0,
        bottom: 1
    )

    /// ガラスの下端に乗せる光沢。縁が光ることで「板」ではなく「ガラスの厚み」に見える。
    static let glassEdgeHighlight = smoothScrim(
        color: .white,
        fadeStart: 0,
        top: 0,
        bottom: 0.14
    )

    // MARK: - Ink (text / primary dots)

    static let ink = Color.white
    static let inkDim = Color.white.opacity(0.40)
    static let inkMute = Color.white.opacity(0.22)
    /// 空 dot / grid ghost 用
    static let inkGhost = Color.white.opacity(0.08)

    // MARK: - Schematic lines

    static let lineFaint = Color.white.opacity(0.06)
    static let lineDefault = Color.white.opacity(0.12)
    static let lineStrong = Color.white.opacity(0.24)

    // MARK: - Signal (状態意味色)
    // Nothing 的なモノクロ + amber アクセントから、Agent Notch の多状態に合わせて 6 色に拡張。

    /// idle / starting
    static let signalIdle = Color(red: 0.545, green: 0.545, blue: 0.545)      // #8B8B8B
    /// thinking / compacting
    static let signalThinking = Color(red: 0.000, green: 0.898, blue: 1.000)  // #00E5FF
    /// tool running / subagent running
    static let signalWorking = Color.white
    /// permission waiting / ask question
    static let signalAlert = Color(red: 1.000, green: 0.722, blue: 0.000)     // #FFB800
    /// error / stop failure
    static let signalError = Color(red: 1.000, green: 0.231, blue: 0.188)     // #FF3B30
    /// done / completed
    static let signalDone = Color(red: 0.204, green: 0.831, blue: 0.600)      // #34D399
    /// plan mode / plan レビュー待ち（ExitPlanMode の確認）
    static let signalPlan = Color(red: 0.635, green: 0.510, blue: 1.000)      // #A282FF
}
