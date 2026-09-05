import Foundation

/// The data structure sent between an Echo server plugin and its corresponding client plugin
public struct PluginPayload: Codable {

    /// The plugin that sent the payload
    public let pluginID: String

    /// The data sent by the plugin
    public let data: Data

    /// An identifier that describes an action to perform, or the type of data contained in ``data``
    public let command: String?

    /// Note: This initializer is maintained for ABI compatibility with existing desktop plugins
    public init(
        pluginID: String,
        data: Data
    ) {
        self.pluginID = pluginID
        self.data = data
        self.command = nil
    }

    public init(
        pluginID: String,
        data: Data,
        command: String?
    ) {
        self.pluginID = pluginID
        self.data = data
        self.command = command
    }

    public enum CodingKeys: String, CodingKey {
        case pluginID = "plugin_id"
        case command
        case data
    }
}
