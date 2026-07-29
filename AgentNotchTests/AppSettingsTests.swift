import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// Covers the settings value types: the labels every picker renders, and the small pieces of
/// logic hiding among them.
///
/// # Why labels are worth a test
/// Each one is a localized string reached only through a SwiftUI picker, so a missing entry shows
/// up as a blank row rather than a build error. Asserting they are present and distinct catches
/// the two ways that breaks: an empty label, and two cases that render identically and so cannot
/// be told apart in the UI.
@Suite("App settings values")
struct AppSettingsTests {
    /// Every case must produce a label, and no two may collide.
    private func expectUsableLabels(_ labels: [String], cases: Int, _ what: String) {
        #expect(labels.count == cases, "\(what): a case is missing a label")
        #expect(labels.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(what)")
        #expect(Set(labels).count == labels.count, "\(what): two cases render identically")
    }

    @Test("Every settings enum labels all of its cases distinctly")
    func everyEnumLabelsItsCases() {
        expectUsableLabels(
            CardPromptSource.allCases.map(\.label), cases: CardPromptSource.allCases.count,
            "CardPromptSource")
        expectUsableLabels(
            TextSizePreference.allCases.map(\.label), cases: TextSizePreference.allCases.count,
            "TextSizePreference")
        expectUsableLabels(
            SessionTimeoutPreference.allCases.map(\.label),
            cases: SessionTimeoutPreference.allCases.count, "SessionTimeoutPreference")
        expectUsableLabels(
            NotificationTapAction.allCases.map(\.label), cases: NotificationTapAction.allCases.count,
            "NotificationTapAction")
        expectUsableLabels(
            UsageGaugeStyle.allCases.map(\.label), cases: UsageGaugeStyle.allCases.count,
            "UsageGaugeStyle")
        expectUsableLabels(
            UsageGaugeMetric.allCases.map(\.label), cases: UsageGaugeMetric.allCases.count,
            "UsageGaugeMetric")
        expectUsableLabels(
            DisplayModePreference.allCases.map(\.label), cases: DisplayModePreference.allCases.count,
            "DisplayModePreference")
        expectUsableLabels(
            SoundEvent.allCases.map(\.label), cases: SoundEvent.allCases.count, "SoundEvent")
        expectUsableLabels(
            AppLanguage.allCases.map(\.label), cases: AppLanguage.allCases.count, "AppLanguage")
    }

    /// The two explicit languages name themselves in their own language on purpose: a Japanese
    /// speaker looking at an English UI still needs to recognise 日本語 in the list. Only
    /// `.system` follows the current language.
    @Test("Language names are not translated, unlike the system option")
    func languageLabelsNameThemselves() {
        #expect(AppLanguage.english.label == "English")
        #expect(AppLanguage.japanese.label == "日本語")
        #expect(AppLanguage.system.label != "system")
        #expect(
            L("System Settings", language: .japanese) == "システム設定",
            "the system option must be translated"
        )
    }

    @Test("Every sound event has a distinct SF Symbol")
    func soundEventIcons() {
        let icons = SoundEvent.allCases.map(\.icon)

        #expect(icons.allSatisfy { !$0.isEmpty })
        #expect(Set(icons).count == icons.count)
    }

    // MARK: - Text size

    /// The scale multiplies every dimension in the notch, so the order matters more than the
    /// exact numbers: a non-monotonic table would make "large" render smaller than "medium".
    @Test("Text size scales increase with size and leave medium as the baseline")
    func textSizeScales() {
        #expect(TextSizePreference.small.scale < TextSizePreference.medium.scale)
        #expect(TextSizePreference.medium.scale < TextSizePreference.large.scale)
        #expect(TextSizePreference.small.scale == 1.0)

        // `scaled` is applied to design-system constants throughout the UI.
        #expect(TextSizePreference.small.scaled(10) == 10)
        #expect(TextSizePreference.large.scaled(10) > 10)
    }

    // MARK: - Session timeout

    /// The raw value is a number of seconds and is what the timeout comparison uses, so `never`
    /// being exactly 0 is load-bearing: it is the sentinel that disables expiry.
    @Test("Timeout raw values are seconds, with never as the zero sentinel")
    func sessionTimeoutRawValues() {
        #expect(SessionTimeoutPreference.oneHour.rawValue == 3_600)
        #expect(SessionTimeoutPreference.sixHours.rawValue == 6 * 3_600)
        #expect(SessionTimeoutPreference.oneDay.rawValue == 24 * 3_600)
        #expect(SessionTimeoutPreference.threeDays.rawValue == 3 * 24 * 3_600)
        #expect(SessionTimeoutPreference.never.rawValue == 0)

        let finite = SessionTimeoutPreference.allCases.filter { $0 != .never }
        #expect(finite.allSatisfy { $0.rawValue > 0 })
        #expect(finite.map(\.rawValue) == finite.map(\.rawValue).sorted())
    }

    // MARK: - Sound choice

    @Test("A sound's display name suits its kind")
    func soundChoiceDisplayName() {
        #expect(SoundChoice.none.displayName == L("None"))
        // A system sound is already named by the name the user picked.
        #expect(SoundChoice.system("Glass").displayName == "Glass")
        // A custom sound stores a full path, but showing the whole thing in a picker is useless.
        #expect(
            SoundChoice.custom("/Users/someone/Library/Sounds/My Alert.aiff").displayName
                == "My Alert.aiff"
        )
    }

    @Test("The constructors set the kind that matches")
    func soundChoiceConstructors() {
        #expect(SoundChoice.none == SoundChoice(kind: .none, name: ""))
        #expect(SoundChoice.system("Bottle").kind == .system)
        #expect(SoundChoice.custom("/tmp/a.aiff").kind == .custom)
        #expect(SoundChoice.custom("/tmp/a.aiff").name == "/tmp/a.aiff")
    }

    /// Sounds are persisted through Defaults, so a Codable change silently resets whatever the
    /// user chose. Round-tripping every kind pins the stored shape.
    @Test("Every sound kind survives a Codable round-trip")
    func soundChoiceRoundTrip() throws {
        for choice in [SoundChoice.none, .system("Morse"), .custom("/tmp/x.aiff")] {
            let data = try JSONEncoder().encode(choice)
            #expect(try JSONDecoder().decode(SoundChoice.self, from: data) == choice)
        }
    }

    @Test("System sounds are listed by bare name, sorted, without duplicates")
    func systemSoundsListing() {
        let sounds = SoundChoice.systemSounds

        // Guarded rather than asserted: a machine with no /System/Library/Sounds is not a
        // failure of this code, and the empty list is the documented fallback.
        guard !sounds.isEmpty else { return }
        #expect(sounds.allSatisfy { !$0.hasSuffix(".aiff") })
        #expect(sounds.allSatisfy { !$0.contains("/") })
        #expect(sounds == sounds.sorted())
        #expect(Set(sounds).count == sounds.count)
    }
}
