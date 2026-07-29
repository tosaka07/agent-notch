import AgentNotchCore
import Foundation

/// Owns the schema lifecycle for app settings stored in UserDefaults.
///
/// The external interface stays at one call from the composition root. Migration ordering,
/// version markers, downgrade protection, and individual transforms remain local to this module.
enum SettingsMigrator {
    static let currentVersion = 1
    static let schemaVersionKey = "settingsSchemaVersion"

    struct Report: Equatable, Sendable {
        enum Outcome: Equatable, Sendable {
            case upToDate
            case migrated
            /// The preferences were written by a newer app. Never rewrite its marker downward.
            case newerSchema
            /// `currentVersion` was raised without adding the required sequential migration.
            case missingMigration
        }

        let startingVersion: Int
        let endingVersion: Int
        let appliedVersions: [Int]
        let outcome: Outcome
    }

    /// Runs every missing migration in order before any caller reads typed settings.
    ///
    /// Each step must be idempotent: the app may terminate after a transform but before its
    /// version marker is persisted, in which case that step runs again on the next launch.
    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Report {
        let storedVersion = readStoredVersion(defaults: defaults)

        guard storedVersion <= currentVersion else {
            Log.persistence.warning(
                "Settings schema \(storedVersion) is newer than supported \(currentVersion); leaving it untouched"
            )
            return Report(
                startingVersion: storedVersion,
                endingVersion: storedVersion,
                appliedVersions: [],
                outcome: .newerSchema
            )
        }

        guard storedVersion < currentVersion else {
            return Report(
                startingVersion: storedVersion,
                endingVersion: storedVersion,
                appliedVersions: [],
                outcome: .upToDate
            )
        }

        var version = storedVersion
        var appliedVersions: [Int] = []

        while version < currentVersion {
            guard applyMigration(from: version, defaults: defaults) else {
                Log.persistence.error(
                    "Missing settings migration from v\(version) to v\(version + 1)"
                )
                return Report(
                    startingVersion: storedVersion,
                    endingVersion: version,
                    appliedVersions: appliedVersions,
                    outcome: .missingMigration
                )
            }

            version += 1
            defaults.set(version, forKey: schemaVersionKey)
            appliedVersions.append(version)
        }

        Log.persistence.info(
            "Migrated settings v\(storedVersion) → v\(version)"
        )
        return Report(
            startingVersion: storedVersion,
            endingVersion: version,
            appliedVersions: appliedVersions,
            outcome: .migrated
        )
    }

    private static func readStoredVersion(defaults: UserDefaults) -> Int {
        guard let number = defaults.object(forKey: schemaVersionKey) as? NSNumber else {
            return 0
        }
        return max(0, number.intValue)
    }

    private static func applyMigration(from version: Int, defaults: UserDefaults) -> Bool {
        switch version {
        case 0:
            migrateV0ToV1(defaults: defaults)
            return true
        default:
            return false
        }
    }

    /// v1 establishes the schema marker for all settings that existed before migrations.
    ///
    /// There is deliberately no transform: the current Defaults keys and representations are the
    /// baseline. The named step still matters because future migrations can now assume v1.
    private static func migrateV0ToV1(defaults _: UserDefaults) {}
}
