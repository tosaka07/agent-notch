import Foundation
import Testing

@testable import AgentNotch

@Suite("Settings schema migrations")
struct SettingsMigratorTests {
    @Test("An existing unversioned install becomes the v1 baseline without losing settings")
    func establishesBaseline() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("ja", forKey: "appLanguage")
        defaults.set(86_400, forKey: "sessionTimeout")

        let report = SettingsMigrator.migrateIfNeeded(defaults: defaults)

        #expect(report.startingVersion == 0)
        #expect(report.endingVersion == 1)
        #expect(report.appliedVersions == [1])
        #expect(report.outcome == .migrated)
        #expect(defaults.integer(forKey: SettingsMigrator.schemaVersionKey) == 1)
        #expect(defaults.string(forKey: "appLanguage") == "ja")
        #expect(defaults.integer(forKey: "sessionTimeout") == 86_400)
    }

    @Test("Running migration twice is idempotent")
    func idempotent() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsMigrator.migrateIfNeeded(defaults: defaults)
        let second = SettingsMigrator.migrateIfNeeded(defaults: defaults)

        #expect(first.outcome == .migrated)
        #expect(second.outcome == .upToDate)
        #expect(second.appliedVersions.isEmpty)
        #expect(defaults.integer(forKey: SettingsMigrator.schemaVersionKey) == 1)
    }

    @Test("An older app never downgrades a newer settings schema")
    func futureSchemaIsUntouched() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(99, forKey: SettingsMigrator.schemaVersionKey)
        defaults.set("future-value", forKey: "futureSetting")

        let report = SettingsMigrator.migrateIfNeeded(defaults: defaults)

        #expect(report.outcome == .newerSchema)
        #expect(report.startingVersion == 99)
        #expect(report.endingVersion == 99)
        #expect(report.appliedVersions.isEmpty)
        #expect(defaults.integer(forKey: SettingsMigrator.schemaVersionKey) == 99)
        #expect(defaults.string(forKey: "futureSetting") == "future-value")
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SettingsMigratorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
