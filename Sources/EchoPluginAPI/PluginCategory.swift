/**
 Defines categories for classifying plugins in the Echo app.
 These categories assist in organizing and navigating through different types of plugins.
 */
public enum PluginCategory: IntegerLiteralType, Comparable {
    /// Relates to data handling and manipulation.
    case data

    /// Pertains to network operations and communication.
    case networking

    /// Involves monitoring and logging functionalities.
    case observability

    /// Deals with performance analysis and optimization.
    case profiling

    /// Encompasses plugins that execute specific actions.
    case actions

    /// Default category for plugins not fitting other categories.
    case uncategorized

    /**
     Compares two `PluginCategory` values based on their raw value.
     */
    public static func < (lhs: PluginCategory, rhs: PluginCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/**
 Extension providing a human-readable name for each `PluginCategory`.
 */
public extension PluginCategory {
    var name: String {
        switch self {
        case .data: return "Data"
        case .networking: return "Networking"
        case .observability: return "Observability"
        case .profiling: return "Profiling"
        case .actions: return "Actions"
        case .uncategorized: return "Uncategorized"
        }
    }
}
