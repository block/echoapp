@testable import NavigationDesktopPlugin
import EchoPluginAPI
import Combine
import XCTest

final class NavigationViewModelTests: XCTestCase {


    // MARK: - disconnect

    func test_disconnect_clearsSnapshot() {
        let viewModel = makeViewModel()
        viewModel.currentSnapshot = makeSnapshot()
        XCTAssertNotNil(viewModel.currentSnapshot)

        viewModel.disconnect()

        XCTAssertNil(viewModel.currentSnapshot)
    }

    // MARK: - Private

    private func makeViewModel() -> NavigationViewModel {
        let connection = CurrentValueSubject<PluginConnection?, Never>(nil)
        return NavigationViewModel(connection: connection)
    }

    private func makeScreen(
        id: String = "screen-default",
        title: String = "Default",
        route: String = "/default",
        className: String? = "DefaultVC",
        parameters: [String: String]? = nil,
        timestamp: Date? = nil
    ) -> NavigationScreen {
        NavigationScreen(
            id: id,
            title: title,
            route: route,
            className: className,
            parameters: parameters,
            timestamp: timestamp
        )
    }

    private func makeSnapshot(
        backstack: [NavigationScreen] = [],
        currentScreen: NavigationScreen = NavigationScreen(
            id: "current",
            title: "Current",
            route: "/current"
        ),
        navigationType: String? = nil,
        timestamp: Date = Date()
    ) -> NavigationSnapshot {
        NavigationSnapshot(
            backstack: backstack,
            currentScreen: currentScreen,
            navigationType: navigationType,
            timestamp: timestamp
        )
    }
}
