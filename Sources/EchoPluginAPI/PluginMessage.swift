import Foundation

public struct PluginMessage: Codable {
    public let command: String?
    public let data: Data

    public init(
        command: String?,
        data: Data
    ) {
        self.command = command
        self.data = data
    }
}
