import SwiftUI

/// Agent Notch's typography tokens. System fonts only (nothing bundled).
///
/// The file splits into two families:
/// - `DSTypography` (this top level): **the notch's own language**. It carries the
///   "industrial instrument" look of compact mode's DotMatrix / PixelCounter / TickerText and
///   the expanded list's cards. This family stays as it is.
/// - `DSTypography.Native`: **semantic native typography for the panel**. Everywhere that
///   should behave as OS UI once expanded — the permission/question banners, the detail
///   screens — uses this. It is based on the point sizes matching macOS's semantic text style
///   hierarchy (headline/body/callout/subheadline/footnote/caption), multiplied by
///   `Defaults[.textSize]` (`TextSizePreference.scale`) so everything scales consistently.
///
/// # Choosing within the own-language family
/// - `display`: large labels (`WAITING` / `#01`). Weight carries the industrial feel. 28–40pt.
/// - `mono`: tool names, values, paths, secondary text. 10–12pt.
/// - `caption`: meta labels (`PROJECT` / `MODEL`). Assumes 9pt uppercase + tracking +0.08em.
///
/// Pixel representations (0–9 digits, state dots) are drawn as bitmaps on a Canvas by
/// `PixelGrid` / `DotMatrix` / `PixelCounter`, and do not depend on a font.
enum DSTypography {
    /// Display: SF Pro Black.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    /// Mono: SF Mono.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Caption: SF Pro Regular.
    static func caption(_ size: CGFloat = 9) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// The semantic native type scale for the panel (list and detail screens).
    ///
    /// | role        | base pt | weight    | use                                      |
    /// |-------------|---------|-----------|------------------------------------------|
    /// | headline    | 13      | semibold  | session titles, banner headings          |
    /// | body        | 13      | regular   | body text (chat markdown, etc.)          |
    /// | callout     | 12      | regular   | button labels, question text             |
    /// | subheadline | 11      | regular   | option labels, subtext                   |
    /// | footnote    | 10      | regular   | tool names / paths / section headings    |
    /// | caption     | 9       | regular   | metadata (times, token counts, tallies)  |
    /// | caption2    | 8       | regular   | the smallest supporting labels           |
    ///
    /// The mono* variants use the same base points with `design: .monospaced`. Use them only for
    /// information that should be monospaced — code, paths, tool names — never running text.
    ///
    /// Each function takes `scale` (= `Defaults[.textSize].scale`), so passing the
    /// `@Default(.textSize)` value straight through from the caller scales everything
    /// consistently.
    enum Native {
        static func headline(_ scale: CGFloat = 1) -> Font {
            .system(size: round(13 * scale), weight: .semibold)
        }

        static func body(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(13 * scale), weight: weight)
        }

        static func callout(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(12 * scale), weight: weight)
        }

        static func subheadline(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(11 * scale), weight: weight)
        }

        static func footnote(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(10 * scale), weight: weight)
        }

        static func caption(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(9 * scale), weight: weight)
        }

        static func caption2(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(8 * scale), weight: weight)
        }

        static func monoCallout(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(12 * scale), weight: weight, design: .monospaced)
        }

        static func monoSubheadline(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(11 * scale), weight: weight, design: .monospaced)
        }

        static func monoFootnote(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(10 * scale), weight: weight, design: .monospaced)
        }

        static func monoCaption(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(9 * scale), weight: weight, design: .monospaced)
        }

        static func monoCaption2(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(8 * scale), weight: weight, design: .monospaced)
        }

        private static func round(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }
    }
}
