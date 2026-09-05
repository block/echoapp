import Combine
import EchoPluginAPI
import Foundation

/// A plugin for viewing and editing key-value stores like UserDefaults
///
/// This plugin manages two types of stores:
/// 1. **Auto-discovered UserDefaults**: Automatically scanned from the app's Preferences directory
/// 2. **Manual stores**: Added via `addStore(_:)`, `addStores(_:)` methods
///
/// ## Usage:
/// ```swift
/// let plugin = EchoKeyValueStorePlugin()
///
/// // Add individual stores
/// plugin.addStore(myCustomStore)
///
/// // Add multiple stores at once
/// plugin.addStores([store1, store2, store3])
///
/// // Remove stores
/// plugin.removeStore(withId: "store-id")
/// plugin.clearStores() // Remove all manual stores
/// ```
///
/// All operations are thread-safe and automatically send snapshots to Echo Desktop.
public final class EchoKeyValueStorePlugin {

    // MARK: - Private Properties

    private var connection: PluginConnection?
    private let queue = DispatchQueue(label: "com.echo.plugin.keyvaluestore")
    private var cancellables = Set<AnyCancellable>()
    private let automaticallyDiscoverStores: Bool

    // Manually added stores (via addStore/addStores methods)
    private var stores: [EchoKeyValueStore] = []
    private let userDefaultsMonitor = UserDefaultsMonitor()

    // Store configuration registry - dynamically discovered UserDefaults suites
    private var storeConfigs: [UserDefaultsStoreConfig] = []

    public init(automaticallyDiscoverStores: Bool = true) {
        self.automaticallyDiscoverStores = automaticallyDiscoverStores
        if automaticallyDiscoverStores {
            storeConfigs = discoverUserDefaultsSuites()
        }
        setupUserDefaultsMonitoring()
    }

    // MARK: - Public API

    /// Adds a store to the current set of stores
    public func addStore(_ store: EchoKeyValueStore) {
        queue.async {
            // Remove any existing store with the same ID before adding
            self.stores.removeAll { $0.id == store.id }
            self.stores.append(store)
            self.sendLatestSnapshot()
        }
    }

    /// Adds multiple stores to the current set of stores
    public func addStores(_ stores: [EchoKeyValueStore]) {
        queue.async {
            for store in stores {
                // Remove any existing store with the same ID before adding
                self.stores.removeAll { $0.id == store.id }
                self.stores.append(store)
            }
            self.sendLatestSnapshot()
        }
    }

    /// Removes a store with the given ID
    public func removeStore(withId storeId: String) {
        queue.async {
            self.stores.removeAll { $0.id == storeId }
            self.sendLatestSnapshot()
        }
    }

    /// Removes all stores
    public func clearStores() {
        queue.async {
            self.stores.removeAll()
            self.sendLatestSnapshot()
        }
    }

    /// Adds or updates a single store (alias for addStore for compatibility)
    public func updateStore(_ store: EchoKeyValueStore) {
        addStore(store)
    }

    /// Sends the current snapshot of all stores
    public func sendSnapshot(shouldRefresh: Bool = false) {
        queue.async {
            if shouldRefresh {
                self.refreshStoreConfigurations()
            }
            self.sendLatestSnapshot()
        }
    }

    /// Manually refresh the list of discovered UserDefaults suites
    public func refreshStoreConfigurations() {
        storeConfigs = discoverUserDefaultsSuites()
    }

    // MARK: - Private Methods

    /// Private method to replace all stores (used internally)
    private func setStores(_ stores: [EchoKeyValueStore]) {
        self.stores = stores
        sendLatestSnapshot()
    }

    private func sendLatestSnapshot() {
        // Combine discovered UserDefaults stores with manually added stores
        let userDefaultsStores = storeConfigs.compactMap { config in
            buildUserDefaultsStore(from: config)
        }

        let allStores = userDefaultsStores + stores
        let snapshot = EchoKeyValueStoreSnapshot(stores: allStores, timestamp: Date())
        sendClientEvent(.updateSnapshot(snapshot))
    }

    private func sendClientEvent(_ event: EchoKeyValueStoreClientEvent) {
        do {
            try connection?.send(event)
        } catch {
            print("Echo: Error Sending Key-Value Store Client Event \(error)")
        }
    }

    /// Checks if a suite name is invalid for UserDefaults initialization
    private func isInvalidSuiteName(_ suiteName: String) -> Bool {
        // Skip empty suite names
        guard !suiteName.isEmpty else { return true }
        
        // Get the current app's bundle identifier
        let bundleId = Bundle.main.bundleIdentifier
        
        // Invalid suite names according to Apple's documentation:
        // - Current application's bundle identifier
        // - NSGlobalDomain
        // - kCFPreferencesAnyApplication, kCFPreferencesCurrentApplication, etc.
        let invalidSuiteNames: Set<String> = [
            "NSGlobalDomain",
            "kCFPreferencesAnyApplication",
            "kCFPreferencesCurrentApplication",
            "kCFPreferencesAnyHost",
            "kCFPreferencesCurrentHost"
        ]
        
        // Check various invalid conditions
        return suiteName == bundleId ||
               invalidSuiteNames.contains(suiteName) ||
               suiteName.hasPrefix(".GlobalPreferences") ||
               suiteName.hasPrefix("com.apple.") ||
               suiteName.contains("loginwindow") ||
               suiteName.contains("SystemUIServer")
    }

    /// Dynamically discovers UserDefaults suites by scanning the Library/Preferences directory
    /// for .plist files and creating store configurations for each discovered suite.
    private func discoverUserDefaultsSuites() -> [UserDefaultsStoreConfig] {
        guard automaticallyDiscoverStores else { return [] }

        var configs: [UserDefaultsStoreConfig] = []

        // Always include the standard UserDefaults
        configs.append(
            UserDefaultsStoreConfig(
                suiteName: nil,
                displayName: "UserDefaults (Standard)",
                sfSymbol: "gearshape.fill"
            )
        )

        // Discover additional suites from the Preferences directory
        let prefsURL = FileManager.default.urls(
            for: .libraryDirectory, 
            in: .userDomainMask
        ).first?.appendingPathComponent("Preferences")

        guard let prefsURL = prefsURL else { return configs }

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: prefsURL.path)
            let suiteNames = files.compactMap { filename -> String? in
                guard filename.hasSuffix(".plist") else { return nil }
                let suiteName = String(filename.dropLast(6)) // Remove ".plist"

                // Filter out invalid suite names and log them for debugging
                if isInvalidSuiteName(suiteName) {
                    print("Echo: Filtered out invalid UserDefaults suite name: '\(suiteName)'")
                    return nil
                }

                return suiteName
            }

            // Create configs for discovered suites
            for suiteName in suiteNames.sorted() {
                let displayName = getDisplayName(for: suiteName)
                let sfSymbol = getSFSymbol(for: suiteName)

                configs.append(UserDefaultsStoreConfig(
                    suiteName: suiteName,
                    displayName: displayName,
                    sfSymbol: sfSymbol
                ))
            }
        } catch {
            print("Echo: Error discovering UserDefaults suites: \(error)")
        }

        return configs
    }

    private func getDisplayName(for suiteName: String) -> String {
        // Provide custom display names for known suites
        switch suiteName {
        case "DebugMenu":
            return "DebugMenu Settings"
        default:
            return suiteName
        }
    }

    private func getSFSymbol(for suiteName: String) -> String {
        // Provide custom SF Symbols for known suites
        switch suiteName {
        case "DebugMenu":
            return "wrench.and.screwdriver.fill"
        case let name where name.contains("debug"):
            return "bug.fill"
        case let name where name.contains("test"):
            return "flask.fill"
        case let name where name.contains("cache"):
            return "externaldrive.fill"
        default:
            return "folder.fill"
        }
    }

    private func buildUserDefaultsStore(from config: UserDefaultsStoreConfig) -> EchoKeyValueStore? {
        guard let userDefaults = config.userDefaults else {
            print("Echo: Cannot build store for config '\(config.name)' - UserDefaults creation failed")
            return nil
        }
        
        let entries = userDefaults.dictionaryRepresentation().compactMap { (key, value) -> EchoKeyValueEntry? in
            let codableValue = EchoCodableValue(from: value)
            let kvType = codableValue.type

            return EchoKeyValueEntry(
                key: key,
                value: codableValue,
                type: kvType,
                isEditable: !config.isReadOnly,
                lastModified: nil, // UserDefaults doesn't track modification dates
                modificationHistory: []
            )
        }

        return EchoKeyValueStore(
            id: config.id,
            name: config.name,
            sfSymbol: config.sfSymbol,
            entries: entries,
            isReadOnly: config.isReadOnly,
            lastUpdated: Date()
        )
    }

    private func setupUserDefaultsMonitoring() {
        userDefaultsMonitor.startMonitoring { [weak self] in
            // App changed UserDefaults - send full snapshot to let desktop do the diffing
            self?.sendSnapshot()
        }
    }

    private func handleDesktopEvent(_ event: EchoKeyValueStoreDesktopEvent) {
        switch event {
        case .requestSnapshot:
            sendSnapshot(shouldRefresh: false)
        case .requestFullRefresh:
            sendSnapshot(shouldRefresh: true)
        case let .updateValue(changeId, storeId, key, newValue, type, desktopTimestamp):
            handleConflictAwareUpdate(
                changeId: changeId,
                storeId: storeId,
                key: key,
                newValue: newValue,
                type: type,
                desktopTimestamp: desktopTimestamp
            )
        case let .deleteKey(changeId, storeId, key, desktopTimestamp):
            handleConflictAwareDelete(
                changeId: changeId,
                storeId: storeId,
                key: key,
                desktopTimestamp: desktopTimestamp
            )
        case let .addKey(changeId, storeId, key, value, type, desktopTimestamp):
            handleConflictAwareAdd(
                changeId: changeId,
                storeId: storeId,
                key: key,
                value: value,
                type: type,
                desktopTimestamp: desktopTimestamp
            )
        }
    }

    // MARK: - Conflict-Aware Operations

    private func handleConflictAwareUpdate(
        changeId: UUID,
        storeId: String,
        key: String,
        newValue: EchoCodableValue,
        type: EchoKeyValueType,
        desktopTimestamp: Date
    ) {
        guard let config = storeConfig(for: storeId) else {
            sendClientEvent(.error(
                storeId: storeId,
                message: "Unknown store ID: \(storeId)"
            ))
            return
        }

        do {
            try updateUserDefaultsValue(for: config, key: key, value: newValue, type: type)

            // Send confirmation
            sendClientEvent(.changeConfirmation(
                changeId: changeId,
                timestamp: Date(),
                success: true
            ))

        } catch {
            // Send error confirmation
            sendClientEvent(.changeConfirmation(
                changeId: changeId,
                timestamp: Date(),
                success: false
            ))

            sendClientEvent(.error(
                storeId: storeId,
                message: "Failed to update \(key): \(error.localizedDescription)"
            ))
        }
    }

    private func handleConflictAwareDelete(
        changeId: UUID,
        storeId: String,
        key: String,
        desktopTimestamp: Date
    ) {
        guard let config = storeConfig(for: storeId) else {
            sendClientEvent(.error(
                storeId: storeId,
                message: "Unknown store ID: \(storeId)"
            ))
            return
        }

        guard let userDefaults = config.userDefaults else {
            sendClientEvent(.changeConfirmation(
                changeId: changeId,
                timestamp: Date(),
                success: false
            ))
            sendClientEvent(.error(
                storeId: storeId,
                message: "Failed to access UserDefaults for store: \(storeId)"
            ))
            return
        }

        userDefaults.removeObject(forKey: key)

        // Send confirmation
        sendClientEvent(.changeConfirmation(
            changeId: changeId,
            timestamp: Date(),
            success: true
        ))
    }

    private func handleConflictAwareAdd(
        changeId: UUID,
        storeId: String,
        key: String,
        value: EchoCodableValue,
        type: EchoKeyValueType,
        desktopTimestamp: Date
    ) {
        guard let config = storeConfig(for: storeId) else {
            sendClientEvent(.error(
                storeId: storeId,
                message: "Unknown store ID: \(storeId)"
            ))
            return
        }

        do {
            try updateUserDefaultsValue(for: config, key: key, value: value, type: type)

            // Send confirmation
            sendClientEvent(.changeConfirmation(
                changeId: changeId,
                timestamp: Date(),
                success: true
            ))

        } catch {
            // Send error confirmation
            sendClientEvent(.changeConfirmation(
                changeId: changeId,
                timestamp: Date(),
                success: false
            ))

            sendClientEvent(.error(
                storeId: storeId,
                message: "Failed to add \(key): \(error.localizedDescription)"
            ))
        }
    }

    // Store lookup helper
    private func storeConfig(for storeId: String) -> UserDefaultsStoreConfig? {
        return storeConfigs.first { $0.id == storeId }
    }

    private func updateUserDefaultsValue(for config: UserDefaultsStoreConfig, key: String, value: EchoCodableValue, type: EchoKeyValueType) throws {
        guard let userDefaults = config.userDefaults else {
            throw EchoKeyValueStoreError.invalidType("Failed to access UserDefaults for store: \(config.name)")
        }
        let anyValue = value.anyValue

        // Type validation and setting
        switch type {
        case .string:
            guard let stringValue = anyValue as? String else {
                throw EchoKeyValueStoreError.invalidType("Expected String for key '\(key)'")
            }
            userDefaults.set(stringValue, forKey: key)

        case .integer:
            guard let intValue = anyValue as? Int32 else {
                throw EchoKeyValueStoreError.invalidType("Expected Int32 for key '\(key)'")
            }
            userDefaults.set(intValue, forKey: key)

        case .integer16:
            guard let intValue = anyValue as? Int16 else {
                throw EchoKeyValueStoreError.invalidType("Expected Int16 for key '\(key)'")
            }
            userDefaults.set(intValue, forKey: key)

        case .integer64:
            guard let intValue = anyValue as? Int64 else {
                throw EchoKeyValueStoreError.invalidType("Expected Int64 for key '\(key)'")
            }
            userDefaults.set(intValue, forKey: key)

        case .float:
            guard let floatValue = anyValue as? Float else {
                throw EchoKeyValueStoreError.invalidType("Expected Float for key '\(key)'")
            }
            userDefaults.set(floatValue, forKey: key)

        case .double:
            guard let doubleValue = anyValue as? Double else {
                throw EchoKeyValueStoreError.invalidType("Expected Double for key '\(key)'")
            }
            userDefaults.set(doubleValue, forKey: key)

        case .boolean:
            guard let boolValue = anyValue as? Bool else {
                throw EchoKeyValueStoreError.invalidType("Expected Bool for key '\(key)'")
            }
            userDefaults.set(boolValue, forKey: key)

        case .data:
            guard let dataValue = anyValue as? Data else {
                throw EchoKeyValueStoreError.invalidType("Expected Data for key '\(key)'")
            }
            userDefaults.set(dataValue, forKey: key)

        case .date:
            guard let dateValue = anyValue as? Date else {
                throw EchoKeyValueStoreError.invalidType("Expected Date for key '\(key)'")
            }
            userDefaults.set(dateValue, forKey: key)

        case .array:
            guard let arrayValue = anyValue as? [Any] else {
                throw EchoKeyValueStoreError.invalidType("Expected Array for key '\(key)'")
            }
            userDefaults.set(arrayValue, forKey: key)

        case .dictionary:
            guard let dictValue = anyValue as? [String: Any] else {
                throw EchoKeyValueStoreError.invalidType("Expected Dictionary for key '\(key)'")
            }
            userDefaults.set(dictValue, forKey: key)

        case .url:
            guard let url = anyValue as? URL else {
                throw EchoKeyValueStoreError.invalidType("Expected URL for key '\(key)'")
            }
            userDefaults.set(url, forKey: key)

        case .unknown:
            // Handle as string fallback
            userDefaults.set(String(describing: anyValue), forKey: key)
        }
    }
}

extension EchoKeyValueStorePlugin: ClientPlugin {
    public static let id: PluginIdentifier = "com.echo.plugin.keyvaluestore"

    public var id: PluginIdentifier { Self.id }
    public var version: String { "1.0.0" }

    public func onConnect(_ connection: PluginConnection) {
        self.connection = connection

        // Listen for desktop events
        connection.receive(EchoKeyValueStoreDesktopEvent.self)
            .sink { [weak self] event in
                self?.handleDesktopEvent(event)
            }
            .store(in: &cancellables)

        queue.async {
            self.sendLatestSnapshot()
        }
    }

    public func onDisconnect() {
        connection = nil
        cancellables.removeAll()
    }

    public func onDesktopPluginActive() {
        // Send fresh snapshot when desktop becomes active
        sendSnapshot()
    }
}

// MARK: - UserDefaults Support

/// Configuration for a UserDefaults store
private struct UserDefaultsStoreConfig {
    let id: String  // Using suite name or identifier as ID
    let name: String
    let sfSymbol: String
    let suiteName: String?
    let isReadOnly: Bool

    var userDefaults: UserDefaults? {
        if let suiteName = suiteName {
            guard let userDefaults = UserDefaults(suiteName: suiteName) else {
                print("Echo: Failed to create UserDefaults with suiteName: '\(suiteName)'")
                return nil
            }
            return userDefaults
        } else {
            return UserDefaults.standard
        }
    }

    init(suiteName: String?, displayName: String? = nil, sfSymbol: String = "gearshape.fill", isReadOnly: Bool = false) {
        if let suiteName = suiteName {
            self.id = suiteName
            self.name = displayName ?? suiteName
            self.suiteName = suiteName
        } else {
            self.id = "standard"
            self.name = displayName ?? "UserDefaults"
            self.suiteName = nil
        }
        self.sfSymbol = sfSymbol
        self.isReadOnly = isReadOnly
    }
}

/// Monitors UserDefaults changes
private class UserDefaultsMonitor {
    private var cancellables = Set<AnyCancellable>()

    func startMonitoring(onChange: @escaping () -> Void) {
        // Monitor UserDefaults changes - let desktop do the diffing
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { _ in
                onChange()
            }
            .store(in: &cancellables)
    }
}
