import Foundation

// MARK: - Communication Protocol

/// Events sent from Client to Desktop
public enum EchoKeyValueStoreClientEvent: Codable {
    /// Client sends full snapshot of all stores (initial load, refresh, or any change detected)
    /// Desktop performs diffing to determine what changed for visual feedback
    case updateSnapshot(EchoKeyValueStoreSnapshot)

    /// Client reports an error occurred
    case error(storeId: String?, message: String)

    /// Client confirms a desktop-initiated change was applied successfully
    case changeConfirmation(changeId: UUID, timestamp: Date, success: Bool)

    /// Client reports a conflict occurred (desktop change rejected due to concurrent app change)
    case changeConflict(
        changeId: UUID,
        key: String,
        appValue: EchoCodableValue,
        desktopValue: EchoCodableValue,
        appTimestamp: Date,
        desktopTimestamp: Date
    )
}

/// Events sent from Desktop to Client
public enum EchoKeyValueStoreDesktopEvent: Codable {
    /// Desktop requests client to send current snapshot
    case requestSnapshot

    /// Desktop requests client to update a value (with conflict resolution support)
    case updateValue(
        changeId: UUID,
        storeId: String,
        key: String,
        newValue: EchoCodableValue,
        type: EchoKeyValueType,
        timestamp: Date
    )

    /// Desktop requests client to delete a key (with conflict resolution support)
    case deleteKey(
        changeId: UUID,
        storeId: String,
        key: String,
        timestamp: Date
    )

    /// Desktop requests client to add a new key (with conflict resolution support)
    case addKey(changeId: UUID, storeId: String, key: String, value: EchoCodableValue, type: EchoKeyValueType, timestamp: Date)

    /// Desktop requests client to perform full refresh/resync
    case requestFullRefresh
}
