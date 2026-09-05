import Foundation

/**
 A data type used by EchoPluginUI. Sending this from the client enables an easy path to
 developing plugins with a full featured and dynamic `Table` view.
 */
public struct EchoTableRow: Identifiable, Codable {
    public let id: String
    public var columnItems: [String: String]

    /// Initializes a `EchoTableRow` with a unique identifier and a dictionary of column data.
    /// - Parameters:
    ///   - id: The unique identifier for the row, uuid provided by default.
    ///   - columnItems: A dictionary containing key-value pairs for the row's columns.
    public init(id: String = UUID().uuidString, columnItems: [String: String]) {
        self.id = id
        self.columnItems = columnItems
    }
}
