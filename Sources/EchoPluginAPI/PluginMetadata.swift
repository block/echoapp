import SwiftUI

/**
 `DesktopPluginMetadata` struct encapsulates essential information about a plugin used in the Echo app.
 It includes metadata such as the plugin's unique identifier, version, category, display name, icon, description,
 organization details, and target application information. This metadata is crucial for plugin management, identification, and display within the Echo app ecosystem.
 */
public struct DesktopPluginMetadata {

    /// Unique identifier for routing requests between the client and desktop application.
    /// Should follow reverse-domain-name syntax, e.g., com.company.xyz.networking.
    public let id: PluginIdentifier

    /// Version number of the plugin, adhering to Semantic Versioning guidelines.
    /// Increment the major version to indicate breaking changes incompatible with earlier ClientPlugin versions.
    public let version: String

    /// Category under which the plugin is classified in the UI for easier navigation.
    public let category: PluginCategory

    /// Display name of the plugin as it will appear in the UI.
    /// e.g., Networking
    public let displayName: String

    /// Icon representing the plugin, displayed next to its name in the UI.
    public let icon: Image

    /// Brief description outlining the plugin's functionality and use cases.
    public let description: String

    /// Identifier representing the organization that owns and maintains this plugin.
    /// Should follow reverse-domain-name syntax, e.g., com.company.xyz.
    public let orgId: String

    /// Display name of the organization as it will appear in the UI.
    /// e.g., XYZ, Inc.
    public let orgDisplayName: String

    /// Identifier of the client application this plugin is intended for.
    /// The desktop app will prioritize plugins matching the targets on the connected client and group them above other plugins.
    /// e.g., com.company.xyz.app or com.company.xyz.*
    public let targetAppId: String?

    /// Display name of the target application as it will appear in the UI.
    /// e.g., XYZ App
    public let targetAppDisplayName: String?
    
    /// Whether this plugin is desktop-only and shouldn't wait for a message from the client to be enabled in the sidebar.
    /// Defaults to false if not specified
    public let desktopOnly: Bool

    /**
     Initializes a new `DesktopPluginMetadata` instance (legacy compatibility).
     */
    public init(
        id: PluginIdentifier,
        version: String,
        category: PluginCategory,
        displayName: String,
        icon: Image,
        description: String,
        orgId: String = "com.echo.unidentified",
        orgDisplayName: String = "Unidentified",
        targetAppId: String? = nil,
        targetAppDisplayName: String? = nil
    ) {
        self.id = id
        self.version = version
        self.category = category
        self.displayName = displayName
        self.icon = icon
        self.description = description
        self.orgId = orgId
        self.orgDisplayName = orgDisplayName
        self.targetAppId = targetAppId
        self.targetAppDisplayName = targetAppDisplayName
        self.desktopOnly = false // Default value for legacy compatibility
    }

    /**
     Initializes a new `DesktopPluginMetadata` instance.
     - Parameters:
     - id: Unique identifier for routing requests between the client and desktop application.
     - version: Version number of the plugin, adhering to Semantic Versioning guidelines.
     - category: Category under which the plugin is classified in the UI for easier navigation.
     - displayName: Display name of the plugin as it will appear in the UI.
     - icon: Icon representing the plugin, displayed next to its name in the UI.
     - description: Brief description outlining the plugin's functionality and use cases.
     - orgId: Identifier representing the organization that owns and maintains this plugin. Defaults to "com.echo.unidentified".
     - orgDisplayName: Display name of the organization as it will appear in the UI. Defaults to "Unidentified".
     - targetAppId: Identifier of the client application this plugin is intended for. Defaults to nil.
     - targetAppDisplayName: Display name of the target application as it will appear in the UI. Defaults to nil.
     - desktopOnly: Whether this plugin is desktop-only. Defaults to false.
     */
    public init(
        id: PluginIdentifier,
        version: String,
        category: PluginCategory,
        displayName: String,
        icon: Image,
        description: String,
        orgId: String = "com.echo.unidentified",
        orgDisplayName: String = "Unidentified",
        targetAppId: String? = nil,
        targetAppDisplayName: String? = nil,
        desktopOnly: Bool = false
    ) {
        self.id = id
        self.version = version
        self.category = category
        self.displayName = displayName
        self.icon = icon
        self.description = description
        self.orgId = orgId
        self.orgDisplayName = orgDisplayName
        self.targetAppId = targetAppId
        self.targetAppDisplayName = targetAppDisplayName
        self.desktopOnly = desktopOnly
    }
}

extension DesktopPluginMetadata {

    /// Errors that can occur when loading plugin metadata from a plist file
    public enum PluginMetadataError: LocalizedError {
        case fileNotFound(String)
        case invalidPlistFormat(String)
        case missingRequiredField(String)
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let fileName):
                return "Failed to find or load \(fileName).plist from bundle"
            case .invalidPlistFormat(let fileName):
                return "Failed to parse \(fileName).plist - invalid format"
            case .missingRequiredField(let fieldName):
                return "Required field '\(fieldName)' is missing or empty in plugin metadata"
            }
        }
    }

    /// Function to load the plugin metadata from a plist file located in the specified bundle.
    /// - Parameters:
    ///   - bundle: The bundle where the plist file is located.
    ///   - fileName: The name of the plist file (without the `.plist` extension).
    /// - Returns: An instance of `DesktopPluginMetadata` with values mapped from the plist.
    /// - Throws: `PluginMetadataError` if required fields are missing or if there are issues loading the plist.
    public static func loadFromPlist(in bundle: Bundle, fileName: String = "PluginInfo") throws -> DesktopPluginMetadata {
        // Load and parse the plist file
        guard let url = bundle.url(forResource: fileName, withExtension: "plist") else {
            throw PluginMetadataError.fileNotFound(fileName)
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PluginMetadataError.fileNotFound(fileName)
        }
        
        let plist: [String: Any]
        do {
            guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw PluginMetadataError.invalidPlistFormat(fileName)
            }
            plist = dict
        } catch {
            throw PluginMetadataError.invalidPlistFormat(fileName)
        }
        
        // Validate and extract required fields
        guard let id = plist["id"] as? String, !id.isEmpty else {
            throw PluginMetadataError.missingRequiredField("id")
        }
        
        guard let version = plist["version"] as? String, !version.isEmpty else {
            throw PluginMetadataError.missingRequiredField("version")
        }
        
        guard let categoryRawValue = plist["category"] as? Int else {
            throw PluginMetadataError.missingRequiredField("category")
        }
        let category = PluginCategory(rawValue: categoryRawValue) ?? .uncategorized
        
        guard let displayName = plist["displayName"] as? String, !displayName.isEmpty else {
            throw PluginMetadataError.missingRequiredField("displayName")
        }
        
        guard let description = plist["description"] as? String, !description.isEmpty else {
            throw PluginMetadataError.missingRequiredField("description")
        }
        
        // Optional fields with defaults
        let sfSymbolName = plist["sfSymbolName"] as? String
        let orgId = plist["orgId"] as? String ?? "com.echo.unidentified"
        let orgDisplayName = plist["orgDisplayName"] as? String ?? "Unidentified"
        let targetAppId = plist["targetAppId"] as? String
        let targetAppDisplayName = plist["targetAppDisplayName"] as? String
        let desktopOnly = plist["desktopOnly"] as? Bool ?? false
        
        // Create the DesktopPluginMetadata object
        return DesktopPluginMetadata(
            id: id,
            version: version,
            category: category,
            displayName: displayName,
            icon: Image(systemName: sfSymbolName ?? "questionmark.circle"),
            description: description,
            orgId: orgId,
            orgDisplayName: orgDisplayName,
            targetAppId: targetAppId,
            targetAppDisplayName: targetAppDisplayName,
            desktopOnly: desktopOnly
        )
    }
}
