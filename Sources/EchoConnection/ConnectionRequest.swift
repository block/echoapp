import Foundation

/// Request sent when the Echo desktop app wants to connect to a client
public struct ConnectionRequest: Codable {

    /// If the client chooses to connect, it should establish a web socket connection with this URL.
    public var serverURL: URL

    public init(serverURL: URL) {
        self.serverURL = serverURL
    }

    public enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
    }
}
