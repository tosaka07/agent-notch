import SwiftUI

/// A visual reference for the glyph shown for each session state.
///
/// This intentionally uses `StateGlyphView` rather than static illustrations so the
/// guide always stays in sync with the glyphs and motion shown in the notch.
struct GlyphGuideSettings: View {
    var body: some View {
        Form {
            Section {
                Text(
                    l10n: """
                        These animated dot patterns show what the current session is doing. \
                        Shape is the primary signal; color provides a secondary cue.
                        """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(l10n: "Session glyphs")
            }

            Section {
                ForEach(GlyphLegend.all) { entry in
                    GlyphGuideRow(entry: entry)
                }
            }

            Section {
                Text(
                    l10n: """
                        When subagents are active, their grid replaces the standby, thinking, \
                        and working glyphs. Approval requests, questions, errors, and completion stay \
                        visible because they need your attention.
                        """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(l10n: "Which glyph takes priority?")
            }
        }
    }
}

private struct GlyphGuideRow: View {
    let entry: GlyphLegend.Entry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            StateGlyphView(state: entry.state, size: 34)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title)
                    .font(.headline)
                Text(verbatim: entry.sessionStates)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: entry.explanation)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
