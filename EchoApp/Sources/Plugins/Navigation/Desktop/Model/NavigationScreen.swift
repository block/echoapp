import Foundation

/// Represents a single screen in the navigation stack
public struct NavigationScreen: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let route: String
    public let className: String?
    public let parameters: [String: String]?
    public let timestamp: Date?

    public init(
        id: String,
        title: String,
        route: String,
        className: String? = nil,
        parameters: [String: String]? = nil,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.route = route
        self.className = className
        self.parameters = parameters
        self.timestamp = timestamp
    }
}
