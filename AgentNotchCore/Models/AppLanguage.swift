import Foundation
import os

/// Language used for Agent Notch's own interface.
///
/// `.system` follows the language selected by macOS. The explicit choices are
/// read at launch, so changing this setting takes effect after relaunching.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case english
    case japanese

    public var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .japanese: Locale(identifier: "ja")
        }
    }
}

/// Process-wide locale for strings owned by `AgentNotchCore`.
///
/// Core cannot depend on the GUI target's Defaults package, so the composition
/// root initializes this value at launch from the saved app language.
public enum AppLocalization {
    private static let languageLock = OSAllocatedUnfairLock(initialState: AppLanguage.system)

    public static var language: AppLanguage {
        get { languageLock.withLock { $0 } }
        set { languageLock.withLock { $0 = newValue } }
    }

    public static func localized(_ value: String.LocalizationValue) -> String {
        localized(value, in: .module)
    }

    /// Resolves a Core string for an explicit language without changing process-wide state.
    public static func localized(
        _ value: String.LocalizationValue,
        language: AppLanguage
    ) -> String {
        localized(value, in: .module, language: language)
    }

    /// Resolves a localized value from the caller's resource bundle.
    ///
    /// SwiftPM and Foundation discover supported localizations from `.lproj`
    /// resources. Explicit choices use Foundation's preferred-localization API;
    /// `.system` leaves bundle selection entirely to the process preferences.
    public static func localized(
        _ value: String.LocalizationValue,
        in bundle: Bundle
    ) -> String {
        localized(value, in: bundle, language: language)
    }

    /// Explicit-language variant used by tests and previews that may run concurrently.
    public static func localized(
        _ value: String.LocalizationValue,
        in bundle: Bundle,
        language selectedLanguage: AppLanguage
    ) -> String {
        let selectedBundle = localizedBundle(
            in: bundle,
            for: selectedLanguage
        )
        return String(
            localized: value,
            bundle: selectedBundle,
            locale: selectedLanguage.locale
        )
    }

    private static func localizedBundle(
        in bundle: Bundle,
        for language: AppLanguage
    ) -> Bundle {
        let preferences: [String]
        switch language {
        case .system:
            return bundle
        case .english:
            preferences = ["en"]
        case .japanese:
            preferences = ["ja"]
        }

        guard
            let localization = Bundle.preferredLocalizations(
                from: bundle.localizations,
                forPreferences: preferences
            ).first,
            let path = bundle.path(
                forResource: localization,
                ofType: "lproj"
            ),
            let localizedBundle = Bundle(path: path)
        else {
            return bundle
        }
        return localizedBundle
    }
}
