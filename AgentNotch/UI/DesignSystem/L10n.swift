import AgentNotchCore
import SwiftUI

/// Localization helpers for the GUI target.
///
/// UI strings live in the standard SwiftPM `en.lproj` and `ja.lproj`
/// directories. Package resources resolve through `Bundle.module`, not
/// `Bundle.main`, so always go through these helpers.
extension Text {
    /// A localized text resolved against this module's string catalog.
    init(l10n value: String.LocalizationValue) {
        self.init(verbatim: L(value))
    }
}

/// Returns a localized string from this module's string catalog.
/// Use in non-`Text` contexts (accessibility labels, `help`, menu titles).
/// The single-letter name is deliberate: it appears at nearly every
/// user-visible string, where a longer name would drown out the text itself.
// swift-format-ignore: AlwaysUseLowerCamelCase
func L(_ value: String.LocalizationValue) -> String {
    AppLocalization.localized(value, in: .module)
}

/// Explicit-language variant for tests and previews that must not mutate global app state.
// swift-format-ignore: AlwaysUseLowerCamelCase
func L(_ value: String.LocalizationValue, language: AppLanguage) -> String {
    AppLocalization.localized(value, in: .module, language: language)
}
