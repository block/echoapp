import Foundation

// Shared wire types for the Debug Menu plugin. Both the desktop plugin and
// `echoapp` depend on this target so renames or new cases are caught at
// compile time instead of silently desyncing the JSON protocol.
//
// Client apps embed a mirror of these wire types. Keep them in sync — when
// adding a case on a client side, mirror it here.

// MARK: - Snapshot

public struct EchoDebugMenuSnapshot: Codable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sections: [EchoDebugMenuSection]
    public let timestamp: Date

    public init(
        schemaVersion: Int = EchoDebugMenuSnapshot.currentSchemaVersion,
        sections: [EchoDebugMenuSection],
        timestamp: Date,
    ) {
        self.schemaVersion = schemaVersion
        self.sections = sections
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sections
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Pre-versioned snapshots default to 0; bump bumps when the wire shape changes.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        sections = try container.decode([EchoDebugMenuSection].self, forKey: .sections)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sections, forKey: .sections)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// MARK: - Section

public struct EchoDebugMenuSection: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let icon: String?
    public let items: [EchoDebugMenuItem]

    public init(id: String, title: String, icon: String?, items: [EchoDebugMenuItem]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.items = items
    }
}

// MARK: - Item

public struct EchoDebugMenuItem: Codable, Identifiable, Hashable {
    public let id: String
    /// Optional short handle (lowercase-hyphen, unique per snapshot) so agents
    /// can address the item as `set-toggle <alias>` instead of the full
    /// breadcrumb id.
    public let alias: String?
    public let title: String
    public let subtitle: String?
    /// One- or two-sentence semantics describing what mutating this item does.
    /// Authored on the client side; surfaced via `echoapp debugmenu describe`.
    public let itemDescription: String?
    public let type: EchoDebugMenuItemType
    public let tags: [String]?

    /// Well-known tag: marks an item whose mutation force-restarts the host
    /// app. Producers MUST tag any item that severs the Echo connection so
    /// `echoapp` can warn the operator and skip waiting for an ack the
    /// device will never send.
    public static let restartOnChangeTag = "restart_on_change"

    public init(
        id: String,
        alias: String? = nil,
        title: String,
        subtitle: String?,
        itemDescription: String? = nil,
        type: EchoDebugMenuItemType,
        tags: [String]? = nil
    ) {
        self.id = id
        self.alias = alias
        self.title = title
        self.subtitle = subtitle
        self.itemDescription = itemDescription
        self.type = type
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case alias
        case title
        case subtitle
        case itemDescription = "description"
        case type
        case tags
    }
}

// MARK: - Item Type

public indirect enum EchoDebugMenuItemType: Codable, Hashable {
    case toggle(isOn: Bool)
    case picker(options: [String], selectedIndex: Int)
    case action
    case textInput(value: String, placeholder: String?)
    case subsection(EchoDebugMenuSection)
    case info(value: String?)
}

// MARK: - Client -> Desktop Events

public enum EchoDebugMenuClientEvent: Codable, Hashable {
    case updateSnapshot(_0: EchoDebugMenuSnapshot)
    case itemUpdated(itemId: String, newType: EchoDebugMenuItemType)
    case actionCompleted(itemId: String, success: Bool, message: String?)
    case error(message: String)
}

// MARK: - Desktop -> Client Events

public enum EchoDebugMenuDesktopEvent: Codable, Hashable {
    case requestSnapshot
    case setToggle(itemId: String, isOn: Bool)
    case selectOption(itemId: String, selectedIndex: Int)
    case executeAction(itemId: String)
    case setTextValue(itemId: String, value: String)
}
