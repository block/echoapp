import Foundation

/// Complete navigation state snapshot
public struct NavigationSnapshot: Codable, Equatable {
    public let backstack: [NavigationScreen]
    public let currentScreen: NavigationScreen
    public let navigationType: String?
    public let timestamp: Date

    public var totalScreens: Int {
        backstack.count + 1
    }

    public init(
        backstack: [NavigationScreen],
        currentScreen: NavigationScreen,
        navigationType: String? = nil,
        timestamp: Date = Date()
    ) {
        self.backstack = backstack
        self.currentScreen = currentScreen
        self.navigationType = navigationType
        self.timestamp = timestamp
    }
}
