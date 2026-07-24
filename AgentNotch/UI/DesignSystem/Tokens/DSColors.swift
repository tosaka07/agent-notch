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
