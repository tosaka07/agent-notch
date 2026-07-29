import SwiftUI

/// The frame every onboarding page shares: a vertically centered body, and a footer rail that
/// owns navigation.
///
/// Splitting the rail out is what keeps "one page = one understanding or one decision" enforceable
/// — the body never carries a decision control, and the rail is the only place a page can advance
/// from. It also keeps the buttons on one line across the whole flow, so the eye does not have to
/// re-find them between pages.
///
/// # Why this layer uses system styles, not the notch's own language
/// This is an ordinary macOS window, so its surface is material and its type and controls come from
/// the system: `.separator`, `.primary` / `.secondary`, the glass button styles. Vibrancy is what
/// keeps text legible over a material, and hard-coded whites do not participate in it. The notch's
/// own dot-glyph vocabulary appears only *inside* the pages, where the product itself is on show.
struct OnboardingScreen<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                content()
            }
            .padding(.horizontal, 44)
            // `.leading` means centered vertically, leading horizontally.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            HStack(spacing: DSSpacing.md) {
                footer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                // The system separator, so the rail's edge matches every other divider in the OS
                // and stays visible against the material at any wallpaper brightness.
                Rectangle().fill(.separator).frame(height: 1)
            }
        }
    }
}

/// A page's opening block: a mono eyebrow, the headline, and one line of supporting text.
///
/// The eyebrow numbers the page ("02 / SESSION") so the flow's length stays legible from any
/// single page. It stays Latin and unlocalized for the same reason the panel's meta labels do —
/// it is a stylized instrument label, not prose.
struct OnboardingHeading: View {
    var eyebrow: String?
    var title: String
    var detail: String?
    /// The opening page's headline, one step up the system scale. Only the first page gets it —
    /// every later page is a section of the same flow.
    var isHero: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if let eyebrow {
                Text(verbatim: eyebrow)
                    .font(DSTypography.mono(9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.tertiary)
            }

            Text(verbatim: title)
                .font(isHero ? .largeTitle : .title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(verbatim: detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The tour's position, as one tick per page.
///
/// Only the explanatory pages are counted. Consent, installation, and the stopped screen are
/// decisions or outcomes rather than reading, and showing "6 of 8" beside a decision suggests
/// it can be advanced past.
struct OnboardingProgressTicks: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.primary)
                    // Depth comes from the hierarchy's own levels, so the ticks track the
                    // material's vibrancy instead of fixed grays.
                    .opacity(opacity(at: index))
                    .frame(width: 18, height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("Step \(current + 1) of \(total)"))
    }

    /// Past steps stay half-lit: the eye reads how far it has come, not only where it is.
    private func opacity(at index: Int) -> Double {
        if index == current { return 1 }
        return index < current ? 0.4 : 0.15
    }
}

/// One disclosure row: a file being written, or a check being run.
struct OnboardingProgressRow: View {
    enum State {
        case waiting
        case active
        case done
    }

    let label: String
    let state: State
    /// The right-hand status word. Omitted while waiting, since the dimmed row already says so.
    var status: String?

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            GlyphView(bitmap: Glyph.task(taskState, color: glyphColor))
                .frame(width: 13, alignment: .leading)

            Text(verbatim: label)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: DSSpacing.sm)

            if let status {
                Text(verbatim: status)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(
                        state == .done ? AnyShapeStyle(DSColors.signalDone) : AnyShapeStyle(.secondary))
            }
        }
        .opacity(state == .waiting ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private var taskState: Glyph.TaskGlyph {
        switch state {
        case .waiting: .todo
        case .active: .active
        case .done: .done
        }
    }

    /// Only completion takes a semantic color. A row still being written is not a state worth
    /// coloring, and two lit colors in a three-row list would read as two different results.
    private var glyphColor: Color? {
        state == .done ? DSColors.signalDone : nil
    }
}
