
/**
 A lightweight, reusable data type for sending simple data over a ``PluginConnection``.
 This type can be used via `pluginConnect.sendEvent` and `.receiveEvents` instead
 of rolling a brand new data type for your plugins.
 */
public struct Event: Identifiable, Codable {
    public let id: String
    public let name: String
    public let metadata: [String: String]
}
