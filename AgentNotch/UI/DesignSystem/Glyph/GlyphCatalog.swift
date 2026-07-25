import SwiftUI

/// グリフ辞書のカタログ（モックの 2a に対応）。
///
/// 実行時には使わない。Xcode Preview でグリフ体系を一望し、
/// 「形が状態を語る / 色が消えても読める」が保てているかを目で確認するためのもの。
struct GlyphCatalog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            section("A · STATE — 13×13（compact 左翼 / カード左列）") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
                    spacing: 14
                ) {
                    ForEach(Self.states, id: \.name) { item in
                        row(name: item.name, description: item.description) {
                            StateGlyphView(state: item.state, size: 26)
                        }
                    }
                }
            }

            section("A' · RING — 使用量の円環（角度順に点灯）") {
                HStack(spacing: 28) {
                    ForEach([12.0, 62.0, 91.0], id: \.self) { percent in
                        HStack(spacing: 10) {
                            GlyphView(
                                bitmap: Glyph.ring(
                                    percent: percent,
                                    lit: percent >= 90 ? DSColors.signalError : DSColors.ink,
                                    track: DSColors.ink.opacity(0.18)
                                )
                            )
                            Text("\(Int(percent))%")
                                .font(DSTypography.mono(10))
                                .foregroundStyle(DSColors.inkDim)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 1) {
                subsection("B · TASK 5×5") {
                    row(name: "TODO", description: "未着手 — 輪郭のみ") { GlyphView(bitmap: Glyph.task(.todo)) }
                    row(name: "ACTIVE", description: "進行中 — 輪郭 + 芯") { GlyphView(bitmap: Glyph.task(.active)) }
                    row(name: "DONE", description: "完了 — 塗り") { GlyphView(bitmap: Glyph.task(.done)) }
                }
                subsection("C · SUBAGENT / MEMBER 5×5") {
                    row(name: "RUNNING", description: "実行中 — 菱形 塗り") { GlyphView(bitmap: Glyph.subagentRunning()) }
                    row(name: "SLOT", description: "空き枠 — 菱形 輪郭") { GlyphView(bitmap: Glyph.subagentIdle()) }
                    row(name: "MEMBER", description: "teammate — 円") { GlyphView(bitmap: Glyph.member()) }
                }
                subsection("D · USAGE 3×3（10 個 = 100%）") {
                    row(name: "FILLED", description: "消費済み — 塗り") {
                        GlyphView(bitmap: Glyph.usageBlock(filled: true, color: DSColors.ink))
                    }
                    row(name: "EMPTY", description: "残量 — 輪郭") {
                        GlyphView(bitmap: Glyph.usageBlock(filled: false, color: DSColors.ink))
                    }
                    HStack(spacing: 5) {
                        ForEach(0..<10, id: \.self) { index in
                            GlyphView(
                                bitmap: Glyph.usageBlock(
                                    filled: Double(index) / 10 < 0.62,
                                    color: DSColors.ink
                                )
                            )
                        }
                    }
                    Text("severity は色だけを変え、目盛りは変えない")
                        .font(DSTypography.mono(8))
                        .foregroundStyle(DSColors.inkMute)
                }
            }
            .padding(.horizontal, 18)

            section("E · NUMERIC 5×7 — 数値と n/m はこの 1 種だけで書く") {
                HStack(spacing: 26) {
                    HStack(spacing: 10) {
                        GlyphView(bitmap: Glyph.framedNumber("62"))
                        Text("FRAMED\n13×13 枠に収めた 2 桁")
                            .font(DSTypography.mono(9))
                            .foregroundStyle(DSColors.inkDim)
                    }
                    GlyphView(bitmap: Glyph.number("62%"))
                    GlyphView(bitmap: Glyph.number("3/7") { index in
                        index == 0 ? DSColors.ink : DSColors.inkDim
                    })
                    GlyphView(bitmap: Glyph.number("$0"))
                }
            }
        }
        .frame(width: 820, alignment: .leading)
        .background(Color(red: 0.078, green: 0.078, blue: 0.086))
    }

    private static let states: [(name: String, description: String, state: Glyph.State)] = [
        ("STANDBY", "idle / starting — 静止した環", .standby),
        ("THINKING", "thinking / compacting — 波形", .thinking),
        ("WORKING", "tool 実行 — 塗りの核", .working),
        ("SWARM(n)", "subagent 並行 n 件 — 9 枠", .swarm(active: 5)),
        ("ALERT", "承認待ち / 質問 — 感嘆", .alert),
        ("PLAN REVIEW", "plan の承認待ち — 三本線", .planReview),
        ("COMPLETE", "完了 — チェック", .complete),
        ("FAULT", "エラー — ×", .fault),
    ]

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("GLYPH DICTIONARY")
                .font(DSTypography.mono(9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))
            Text("形が状態を語る。色は補助であり、色が消えても読める")
                .font(DSTypography.Native.caption())
                .foregroundStyle(DSColors.inkDim)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(DSColors.lineDefault).frame(height: 1) }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DSTypography.mono(9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(DSColors.inkDim)
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func subsection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DSTypography.mono(9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(DSColors.inkDim)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.078, green: 0.078, blue: 0.086))
    }

    private func row<Content: View>(
        name: String,
        description: String,
        @ViewBuilder glyph: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            glyph().frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(DSTypography.mono(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(DSColors.ink.opacity(0.9))
                Text(description)
                    .font(DSTypography.Native.caption())
                    .foregroundStyle(DSColors.inkDim)
            }
        }
    }
}

#Preview("Glyph Dictionary") {
    GlyphCatalog()
}
