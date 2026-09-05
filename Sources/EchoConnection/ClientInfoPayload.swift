import Foundation

/// The data structure sent between the Echo server and a connected client.
/// This is sent any time the client's metadata changes
/// For example, when client plugins are added/removed from the client
public struct ClientInfoPayload: Codable, Equatable {

    /// All client plugins that are currently loaded by the client
    public let clientPluginIDs: [String]

    public init(
        clientPluginIDs: [String]
    ) {
        self.clientPluginIDs = clientPluginIDs
    }

    public enum CodingKeys: String, CodingKey {
        case clientPluginIDs = "client_plugin_ids"
    }
}
