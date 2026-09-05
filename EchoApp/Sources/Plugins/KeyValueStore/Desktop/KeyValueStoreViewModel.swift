import Combine
import EchoPluginAPI
import Foundation
import SwiftUI

public final class KeyValueStoreViewModel: ObservableObject {
    @Published var stores: [EchoKeyValueStore] = []
    @Published var selectedStoreId: String?
    @Published var selectedEntryId: String?
    @Published var searchText: String = ""
    @Published var selectedType: EchoKeyValueType? = nil
    @Published var sortOrder = [KeyPathComparator(\EchoKeyValueEntry.key)]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published public var showingAddForm: Bool = false
    @Published public var showingEditForm: Bool = false
    @Published private(set) var isConnected = false
    
    private var connection: PluginConnection?
    private var cancellables = Set<AnyCancellable>()
    
    // Visual change tracking
    @Published var flashingChanges: [String: ChangeFlash] = [:]
    
    // Conflict resolution tracking
    @Published var pendingChanges: [UUID: PendingChange] = [:]
    @Published var conflicts: [String: ConflictInfo] = [:]
    
    // Timer for cleanup to avoid memory leaks
    private var flashCleanupTimer: Timer?
    private var conflictCleanupTimer: Timer?
    
    // Track initial load to prevent flashing everything on first snapshot
    private var hasInitialLoad = false
    
    // Computed properties for the SplitView
    var selectedStore: EchoKeyValueStore? {
        guard let selectedStoreId = selectedStoreId else { return nil }
        return stores.first(where: { $0.id == selectedStoreId })
    }
    
    deinit {
        flashCleanupTimer?.invalidate()
        conflictCleanupTimer?.invalidate()
    }
    
    // MARK: - Data Structures
    
    struct ChangeFlash: Equatable {
        let type: ChangeType
        let timestamp: Date
        
        enum ChangeType: Equatable {
            case added, updated, deleted
        }
    }
    
    struct PendingChange: Equatable {
        let changeId: UUID
        let storeId: String
        let key: String
        let timestamp: Date
        let changeType: ChangeType
        
        enum ChangeType: Equatable {
            case update(EchoCodableValue, EchoKeyValueType)
            case delete
            case add(EchoCodableValue, EchoKeyValueType)
        }
    }
    
    struct ConflictInfo: Equatable {
        let changeId: UUID
        let key: String
        let appValue: EchoCodableValue
        let desktopValue: EchoCodableValue
        let appTimestamp: Date
        let desktopTimestamp: Date
        let conflictTimestamp: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(conflictTimestamp) > 30.0 // 30 seconds
        }
    }
    
    // MARK: - Public Methods
    
    func setupConnection(_ connection: PluginConnection) {
        self.connection = connection
        isConnected = true
        
        // Listen for client events
        connection
            .receive(EchoKeyValueStoreClientEvent.self)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] event in
                Task { @MainActor in
                    self?.handleClientEvent(event)
                }
            })
            .store(in: &cancellables)
        
        // Setup cleanup timers
        setupCleanupTimers()
    }
    
    func disconnect() {
        connection = nil
        isConnected = false
        cancellables.removeAll()
        flashCleanupTimer?.invalidate()
        hasInitialLoad = false // Reset for next connection
    }
    
    func requestSnapshot() {
        Task { @MainActor in
            isLoading = true
            sendDesktopEvent(.requestSnapshot)
        }
    }

    @MainActor
    func updateValue(storeId: String, key: String, newValue: EchoCodableValue, type: EchoKeyValueType) {
        let changeId = UUID()
        let timestamp = Date()
        
        // Track pending change
        pendingChanges[changeId] = PendingChange(
            changeId: changeId,
            storeId: storeId,
            key: key,
            timestamp: timestamp,
            changeType: .update(newValue, type)
        )
        
        sendDesktopEvent(.updateValue(
            changeId: changeId,
            storeId: storeId,
            key: key,
            newValue: newValue,
            type: type,
            timestamp: timestamp
        ))
    }
    
    @MainActor
    func deleteKey(storeId: String, key: String) {
        let changeId = UUID()
        let timestamp = Date()
        
        // Track pending change
        pendingChanges[changeId] = PendingChange(
            changeId: changeId,
            storeId: storeId,
            key: key,
            timestamp: timestamp,
            changeType: .delete
        )
        
        sendDesktopEvent(.deleteKey(
            changeId: changeId,
            storeId: storeId,
            key: key,
            timestamp: timestamp
        ))
    }
    
    @MainActor
    func addKey(storeId: String, key: String, value: EchoCodableValue, type: EchoKeyValueType) {
        let changeId = UUID()
        let timestamp = Date()
        
        // Track pending change
        pendingChanges[changeId] = PendingChange(
            changeId: changeId,
            storeId: storeId,
            key: key,
            timestamp: timestamp,
            changeType: .add(value, type)
        )
        
        sendDesktopEvent(.addKey(
            changeId: changeId,
            storeId: storeId,
            key: key,
            value: value,
            type: type,
            timestamp: timestamp
        ))
    }
    
    // MARK: - Event Handling
    
    @MainActor
    private func handleClientEvent(_ event: EchoKeyValueStoreClientEvent) {
        switch event {
        case .updateSnapshot(let snapshot):
            // Client sent full snapshot - perform diffing to detect changes and provide visual feedback
            processSnapshotWithDiff(snapshot)
            isLoading = false
            
        case .error(_, let message):
            errorMessage = message
            
        case .changeConfirmation(let changeId, let timestamp, let success):
            // Desktop-initiated change was confirmed by client
            handleChangeConfirmation(changeId: changeId, timestamp: timestamp, success: success)
            
        case .changeConflict(let changeId, let key, let appValue, let desktopValue, let appTimestamp, let desktopTimestamp):
            // Desktop-initiated change conflicted with app change
            handleChangeConflict(
                changeId: changeId,
                key: key,
                appValue: appValue,
                desktopValue: desktopValue,
                appTimestamp: appTimestamp,
                desktopTimestamp: desktopTimestamp
            )
        }
    }
    
    // MARK: - Memory-Safe Timer Management
    
    private func setupCleanupTimers() {
        // Cleanup flash states every 2 seconds
        flashCleanupTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cleanupExpiredFlashes()
            }
        }
        
        // Cleanup expired conflicts every 10 seconds
        conflictCleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cleanupExpiredConflicts()
            }
        }
    }
    
    @MainActor
    private func cleanupExpiredFlashes() {
        let now = Date()
        flashingChanges = flashingChanges.filter { _, flash in
            now.timeIntervalSince(flash.timestamp) < (flash.type == .deleted ? 1.2 : 0.8)
        }
    }
    
    @MainActor
    private func cleanupExpiredConflicts() {
        conflicts = conflicts.filter { _, conflict in
            !conflict.isExpired
        }
    }
    
    // MARK: - Conflict Resolution
    
    @MainActor
    private func handleChangeConfirmation(changeId: UUID, timestamp: Date, success: Bool) {
        // Remove the pending change since it's now confirmed
        pendingChanges.removeValue(forKey: changeId)
        
        if !success {
            // Change failed - could show error to user
            // For now, just remove from pending changes
            print("Change \(changeId) failed")
        }
    }
    
    @MainActor
    private func handleChangeConflict(
        changeId: UUID,
        key: String,
        appValue: EchoCodableValue,
        desktopValue: EchoCodableValue,
        appTimestamp: Date,
        desktopTimestamp: Date
    ) {
        // Remove the pending change since it conflicted
        pendingChanges.removeValue(forKey: changeId)
        
        // Create conflict info for UI display
        let conflictKey = key // Simple key for now, could be "\(storeId)-\(key)" for multiple stores
        conflicts[conflictKey] = ConflictInfo(
            changeId: changeId,
            key: key,
            appValue: appValue,
            desktopValue: desktopValue,
            appTimestamp: appTimestamp,
            desktopTimestamp: desktopTimestamp,
            conflictTimestamp: Date()
        )
        
        print("Conflict detected for key '\(key)': app value updated at \(appTimestamp), desktop tried to update at \(desktopTimestamp)")
    }
    
    // MARK: - Conflict Resolution Helpers
    
    func getConflictInfo(for key: String) -> ConflictInfo? {
        return conflicts[key]
    }
    
    @MainActor
    func retryConflictedChange(for key: String) {
        guard let conflict = conflicts[key] else { return }
        
        // Remove the conflict
        conflicts.removeValue(forKey: key)
        
        // Retry the original change with a new timestamp
        // For now, assume it was an update - in a full implementation, we'd track the original operation type
        if let storeId = selectedStoreId {
            // Determine the type from the desktop value
            let type = conflict.desktopValue.type
            updateValue(storeId: storeId, key: key, newValue: conflict.desktopValue, type: type)
        }
    }
    
    @MainActor
    func acceptAppValue(for key: String) {
        // Simply remove the conflict - app value is already in the store
        conflicts.removeValue(forKey: key)
    }
    
    // MARK: - Snapshot Diffing & Visual Changes
    
    @MainActor
    private func processSnapshotWithDiff(_ snapshot: EchoKeyValueStoreSnapshot) {
        let oldStores = stores
        let newStores = snapshot.stores
        
        // Update stores first
        stores = newStores
        
        // Only flash changes if this isn't the initial load
        let shouldFlash = hasInitialLoad
        
        // Process each store for changes
        for newStore in newStores {
            if let oldStore = oldStores.first(where: { $0.id == newStore.id }) {
                // Store existed, check for entry changes
                if shouldFlash {
                    processStoreChanges(oldStore: oldStore, newStore: newStore)
                }
            } else if shouldFlash {
                // New store - flash all entries as added (only after initial load)
                for entry in newStore.entries {
                    flashChange(storeId: newStore.id, key: entry.key, changeType: .added)
                }
            }
        }
        
        // Check for deleted stores (only after initial load)
        if shouldFlash {
            for oldStore in oldStores {
                if !newStores.contains(where: { $0.id == oldStore.id }) {
                    // Store was deleted - flash all entries as deleted
                    for entry in oldStore.entries {
                        flashChange(storeId: oldStore.id, key: entry.key, changeType: .deleted)
                    }
                }
            }
        }
        
        if selectedStoreId == nil {
            selectedStoreId = newStores.first?.id
        }
        
        // Mark that we've completed the initial load
        hasInitialLoad = true
    }
    
    @MainActor
    private func processStoreChanges(oldStore: EchoKeyValueStore, newStore: EchoKeyValueStore) {
        let oldEntries = Dictionary(uniqueKeysWithValues: oldStore.entries.map { ($0.key, $0) })
        let newEntries = Dictionary(uniqueKeysWithValues: newStore.entries.map { ($0.key, $0) })
        
        // Check for added entries
        for (key, _) in newEntries {
            if oldEntries[key] == nil {
                flashChange(storeId: newStore.id, key: key, changeType: .added)
            }
        }
        
        // Check for updated entries
        for (key, newEntry) in newEntries {
            if let oldEntry = oldEntries[key] {
                if !areEntriesEqual(oldEntry, newEntry) {
                    flashChange(storeId: newStore.id, key: key, changeType: .updated)
                }
            }
        }
        
        // Check for deleted entries
        for (key, _) in oldEntries {
            if newEntries[key] == nil {
                flashChange(storeId: newStore.id, key: key, changeType: .deleted)
            }
        }
    }
    
    private func areEntriesEqual(_ entry1: EchoKeyValueEntry, _ entry2: EchoKeyValueEntry) -> Bool {
        return entry1.key == entry2.key &&
               entry1.value == entry2.value &&
               entry1.type == entry2.type
    }
    
    @MainActor
    private func flashChange(storeId: String, key: String, changeType: ChangeFlash.ChangeType) {
        let flashKey = "\(storeId)-\(key)"
        
        // Set the flash
        flashingChanges[flashKey] = ChangeFlash(type: changeType, timestamp: Date())
        
        // Auto-remove flash after animation duration
        let duration: TimeInterval = changeType == .deleted ? 1.2 : 0.8
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.flashingChanges.removeValue(forKey: flashKey)
        }
    }
    
    func getFlashState(storeId: String, key: String) -> ChangeFlash? {
        let flashKey = "\(storeId)-\(key)"
        return flashingChanges[flashKey]
    }

    @MainActor
    private func sendDesktopEvent(_ event: EchoKeyValueStoreDesktopEvent) {
        guard let connection else {
            errorMessage = "Connect a mobile app before editing key-value stores."
            return
        }

        do {
            try connection.send(event)
        } catch {
            errorMessage = "Failed to send command: \(error.localizedDescription)"
        }
    }
}
