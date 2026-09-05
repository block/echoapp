import Foundation

enum EchoAppDefaultsMigration {
    static let legacyDomain = "xyz.block.Echo"
    static let migrationKey = "xyz.block.echoapp.didMigrateLegacyDefaults"

    static func migrateIfNeeded() {
        migrateIfNeeded(
            from: UserDefaults.standard.persistentDomain(forName: legacyDomain),
            to: .standard
        )
    }

    static func migrateIfNeeded(from legacyValues: [String: Any]?, to defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationKey) else { return }

        if let legacyValues {
            for (key, value) in legacyValues where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationKey)
    }
}
