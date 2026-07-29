import SwiftUI

/// A catalog of the glyph dictionary.
///
/// Not used at runtime. It exists so the whole glyph system can be seen at once in an Xcode
/// Preview, to check by eye that "the shape tells the state / it reads with the color gone"
/// still holds.
struct GlyphCatalog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            section("A · STATE — 13×13 (compact left wing / card left column)") {
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

            section("A' · RING — usage ring (lit in angular order)") {
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
                    row(name: "TODO", description: "todo — outline only") {
                        GlyphView(bitmap: Glyph.task(.todo))
                    }
                    row(name: "ACTIVE", description: "active — outline + core") {
                        GlyphView(bitmap: Glyph.task(.active))
                    }
                    row(name: "DONE", description: "done — filled") { GlyphView(bitmap: Glyph.task(.done)) }
                }
                subsection("C · SUBAGENT / MEMBER 5×5") {
                    row(name: "RUNNING", description: "running — filled diamond") {
                        GlyphView(bitmap: Glyph.subagentRunning())
                    }
                    row(name: "SLOT", description: "free slot — diamond outline") {
                        GlyphView(bitmap: Glyph.subagentIdle())
                    }
                    row(name: "MEMBER", description: "teammate — block") { GlyphView(bitmap: Glyph.member()) }
                }
                subsection("D · USAGE 3×3 (10 blocks = 100%)") {
                    row(name: "FILLED", description: "consumed — filled") {
                        GlyphView(bitmap: Glyph.usageBlock(filled: true, color: DSColors.ink))
                    }
                    row(name: "EMPTY", description: "remaining — outline") {
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
                    Text("severity changes only the color, never the ticks")
                        .font(DSTypography.mono(8))
                        .foregroundStyle(DSColors.inkMute)
                }
            }
            .padding(.horizontal, 18)

            section("E · NUMERIC 5×7 — numbers and n/m use this one face only") {
                HStack(spacing: 26) {
                    HStack(spacing: 10) {
                        GlyphView(bitmap: Glyph.framedNumber("62"))
                        Text("FRAMED\ntwo digits fitted into the 13×13 frame")
                            .font(DSTypography.mono(9))
                            .foregroundStyle(DSColors.inkDim)
                    }
                    GlyphView(bitmap: Glyph.number("62%"))
                    GlyphView(
                        bitmap: Glyph.number("3/7") { index in
                            index == 0 ? DSColors.ink : DSColors.inkDim
                        })
                    GlyphView(bitmap: Glyph.number("$0"))
                }
            }

            section("F · DOZING 21×13 — the empty state, with no session at all") {
                HStack(spacing: 26) {
                    DozingGlyphView(height: 60)
                    Text(
                        "The empty state is not an error, so no negative figure is used.\nThe outline reuses the same circle as A''s usage ring."
                    )
                    .font(DSTypography.mono(9))
                    .foregroundStyle(DSColors.inkDim)
                }
            }
        }
        .frame(width: 820, alignment: .leading)
        .background(Color(red: 0.078, green: 0.078, blue: 0.086))
    }

    private static let states: [(name: String, description: String, state: Glyph.State)] = [
        ("STANDBY", "idle / starting — still ring", .standby),
        ("THINKING", "thinking / compacting — waveform", .thinking),
        ("WORKING", "tool execution — filled core", .working),
        ("SWARM(n)", "n subagents in parallel — 9 slots", .swarm(active: 5)),
        ("ALERT", "awaiting approval — exclamation", .alert),
        ("QUESTION", "awaiting an answer — question mark", .question),
        ("PLAN REVIEW", "awaiting plan approval — three lines", .planReview),
        ("COMPLETE", "done — check", .complete),
        ("FAULT", "error — ×", .fault),
    ]

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("GLYPH DICTIONARY")
                .font(DSTypography.mono(9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))
            Text("The shape tells the state; color is secondary, and it reads with the color gone")
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
