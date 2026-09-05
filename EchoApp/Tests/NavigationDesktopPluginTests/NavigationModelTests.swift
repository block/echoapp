@testable import NavigationDesktopPlugin
import XCTest

// MARK: - NavigationScreen Tests

final class NavigationScreenTests: XCTestCase {

    // MARK: - Codable

    func test_encodeDecode_allFields() throws {
        let screen = Factory.makeScreen()
        let decoded = try encodeAndDecode(screen)
        XCTAssertEqual(screen, decoded)
    }

    func test_encodeDecode_optionalFieldsNil() throws {
        let screen = Factory.makeScreen(className: nil, parameters: nil, timestamp: nil)
        let decoded = try encodeAndDecode(screen)
        XCTAssertEqual(screen, decoded)
    }

    // MARK: - Equatable

    func test_equatable_sameValues() {
        let screen1 = Factory.makeScreen()
        let screen2 = Factory.makeScreen()
        XCTAssertEqual(screen1, screen2)
    }

    func test_equatable_differentId() {
        let screen1 = Factory.makeScreen(id: "screen-1")
        let screen2 = Factory.makeScreen(id: "screen-2")
        XCTAssertNotEqual(screen1, screen2)
    }

    func test_equatable_differentTitle() {
        let screen1 = Factory.makeScreen(title: "Home")
        let screen2 = Factory.makeScreen(title: "Settings")
        XCTAssertNotEqual(screen1, screen2)
    }

    func test_equatable_differentRoute() {
        let screen1 = Factory.makeScreen(route: "/home")
        let screen2 = Factory.makeScreen(route: "/settings")
        XCTAssertNotEqual(screen1, screen2)
    }

    func test_equatable_differentClassName() {
        let screen1 = Factory.makeScreen(className: "HomeVC")
        let screen2 = Factory.makeScreen(className: "SettingsVC")
        XCTAssertNotEqual(screen1, screen2)
    }

    func test_equatable_differentParameters() {
        let screen1 = Factory.makeScreen(parameters: ["key": "value1"])
        let screen2 = Factory.makeScreen(parameters: ["key": "value2"])
        XCTAssertNotEqual(screen1, screen2)
    }

    // MARK: - Private

    private func encodeAndDecode<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - NavigationSnapshot Tests

final class NavigationSnapshotTests: XCTestCase {

    func test_encodeDecode() throws {
        let snapshot = Factory.makeSnapshot()
        let decoded = try encodeAndDecode(snapshot)
        XCTAssertEqual(snapshot, decoded)
    }

    func test_encodeDecode_emptyBackstack() throws {
        let snapshot = Factory.makeSnapshot(backstack: [])
        let decoded = try encodeAndDecode(snapshot)
        XCTAssertEqual(snapshot, decoded)
    }

    func test_encodeDecode_nilNavigationType() throws {
        let snapshot = Factory.makeSnapshot(navigationType: nil)
        let decoded = try encodeAndDecode(snapshot)
        XCTAssertEqual(snapshot, decoded)
    }

    // MARK: - Computed Properties

    func test_totalScreens_withBackstack() {
        let snapshot = Factory.makeSnapshot(backstack: [
            Factory.makeScreen(id: "1", title: "Login", route: "/login"),
            Factory.makeScreen(id: "2", title: "Signup", route: "/signup"),
        ])
        XCTAssertEqual(snapshot.totalScreens, 3)
    }

    func test_totalScreens_emptyBackstack() {
        let snapshot = Factory.makeSnapshot(backstack: [])
        XCTAssertEqual(snapshot.totalScreens, 1)
    }

    // MARK: - Equatable

    func test_equatable_differentCurrentScreen() {
        let snapshot1 = Factory.makeSnapshot(
            currentScreen: Factory.makeScreen(id: "1", title: "Home", route: "/home")
        )
        let snapshot2 = Factory.makeSnapshot(
            currentScreen: Factory.makeScreen(id: "2", title: "Settings", route: "/settings")
        )
        XCTAssertNotEqual(snapshot1, snapshot2)
    }

    func test_equatable_differentBackstack() {
        let snapshot1 = Factory.makeSnapshot(backstack: [
            Factory.makeScreen(id: "1", title: "Login", route: "/login"),
        ])
        let snapshot2 = Factory.makeSnapshot(backstack: [])
        XCTAssertNotEqual(snapshot1, snapshot2)
    }

    // MARK: - Private

    private func encodeAndDecode<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Factory

private enum Factory {

    static let fixedDate = Date(timeIntervalSince1970: 1708300000)

    static func makeScreen(
        id: String = "screen-default",
        title: String = "Home",
        route: String = "/home",
        className: String? = "HomeViewController",
        parameters: [String: String]? = ["userId": "123"],
        timestamp: Date? = fixedDate
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

    static func makeSnapshot(
        backstack: [NavigationScreen] = [
            makeScreen(id: "back-1", title: "Login", route: "/login"),
        ],
        currentScreen: NavigationScreen = makeScreen(),
        navigationType: String? = "push",
        timestamp: Date = fixedDate
    ) -> NavigationSnapshot {
        NavigationSnapshot(
            backstack: backstack,
            currentScreen: currentScreen,
            navigationType: navigationType,
            timestamp: timestamp
        )
    }
}
