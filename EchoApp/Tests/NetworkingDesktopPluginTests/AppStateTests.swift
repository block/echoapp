@testable import NetworkingDesktopPlugin

import AppKit
import ComposableArchitecture
import EchoPluginAPI
import Foundation
import IdentifiedCollections
import XCTest

final class AppStateTests: XCTestCase {

    // MARK: - Tests - Codable

    func test_encodeDecode() throws {
        let state = Factory.makeAppState()
        let decodedState = try encodeAndDecode(state: state)

        var expectedState = state
        // Some state is intentionally not persisted:
        expectedState.selectedRequestTab = .body
        expectedState.selectedResponseTab = .body

        XCTAssertEqual(decodedState, expectedState)
    }

    func test_encode_filtersOutIncompleteExchanges() throws {
        let state = Factory.makeAppState(
            exchanges: [
                Factory.Exchanges.pendingResponse,
                Factory.Exchanges.sendingResponse,
                Factory.Exchanges.finalizedResponse,
            ],
            selectedExchange: Factory.Exchanges.pendingResponse
        )
        let decodedState = try encodeAndDecode(state: state)
        XCTAssertEqual(decodedState.exchanges, [Factory.Exchanges.finalizedResponse])
        XCTAssertNil(decodedState.selectedExchange)
    }

    func test_filterCollection_encodeDecodePreservesSearchText() throws {
        let filters = FilterCollection(searchText: "payment")

        let decodedFilters = try JSONDecoder().decode(
            FilterCollection.self,
            from: JSONEncoder().encode(filters)
        )

        XCTAssertEqual(decodedFilters.searchText, "payment")
    }

    func test_filterCollection_decodeUsesLegacyEndpointPath() throws {
        let data = Data(
            """
            {
              "hideFailedRequests": false,
              "hideSuccessfulRequests": true,
              "endpointPath": "legacy"
            }
            """.utf8
        )

        let filters = try JSONDecoder().decode(FilterCollection.self, from: data)

        XCTAssertEqual(filters.searchText, "legacy")
        XCTAssertFalse(filters.hideFailedRequests)
        XCTAssertTrue(filters.hideSuccessfulRequests)
    }

    func test_filterCollection_decodeDefaultsMissingExcludedEndpointPaths() throws {
        let data = Data(
            """
            {
              "hideFailedRequests": true,
              "hideSuccessfulRequests": false
            }
            """.utf8
        )

        let filters = try JSONDecoder().decode(FilterCollection.self, from: data)

        XCTAssertTrue(filters.hideFailedRequests)
        XCTAssertFalse(filters.hideSuccessfulRequests)
        XCTAssertEqual(filters.excludedEndpointPaths, [])
    }

    func test_filterCollection_normalizesExcludedEndpointPaths() {
        let filters = FilterCollection(excludedEndpointPaths: [" /_STATUS ", "/_status", "", "/1.0/Features"])

        XCTAssertEqual(filters.excludedEndpointPaths, ["/_status", "/1.0/features"])
    }

    // MARK: - Tests - Equatable

    func test_equatable() throws {
        let state1 = Factory.makeAppState()
        let state2 = Factory.makeAppState()
        XCTAssertEqual(state1, state2)
        
        // Verify changing any individual property breaks equality
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(exchanges: [])
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(selectedExchange: nil)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(fixturesRepoPath: "/different/path")
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(starredExchanges: [])
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(defaultResponsePolicy: .proxy)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(maxExchangesToKeep: 999)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(enableJsonHighlighting: false)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(assumeProxyingEnabled: false)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(exchangeDetailPaneConfiguration: .request)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(rules: [])
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(responseFixtures: [:])
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(
                filters: .init(
                    hideFailedRequests: true, 
                    hideSuccessfulRequests: false, 
                    searchText: ""
                )
            )
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(detailViewFontSize: 14.0)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(selectedRequestTab: .headers)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(selectedResponseTab: .headers)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(customResponsePolicies: [])
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(showFullURLs: true)
        )
        
        XCTAssertNotEqual(
            Factory.makeAppState(),
            Factory.makeAppState(showTimestamps: true)
        )
    }

    // MARK: - Tests - Filtering

    func test_filteredExchanges_matchesRequestAndResponseContent() {
        let matchingRequestBody = Factory.makeExchange(
            path: "/2.0/example/customer",
            requestBody: #"{"payment_amount":1234}"#,
            responseBody: #"{"ok":true}"#
        )
        let matchingResponseBody = Factory.makeExchange(
            path: "/2.0/example/customer",
            requestBody: #"{"name":"unit"}"#,
            responseBody: #"{"payment_token":"abc"}"#
        )
        let nonMatching = Factory.makeExchange(
            path: "/2.0/example/profile",
            requestBody: #"{"name":"unit"}"#,
            responseBody: #"{"ok":true}"#
        )
        let state = Factory.makeAppState(
            exchanges: [matchingRequestBody, matchingResponseBody, nonMatching],
            filters: .init(searchText: "payment")
        )

        XCTAssertEqual(state.filteredExchanges, [matchingRequestBody, matchingResponseBody])
    }

    func test_filteredExchanges_excludesConfiguredEndpointPaths() {
        let status = Factory.makeExchange(path: "/_status")
        let flags = Factory.makeExchange(path: "/1.0/features/get-flags")
        let payment = Factory.makeExchange(path: "/2.0/example/payment")
        let state = Factory.makeAppState(
            exchanges: [status, flags, payment],
            filters: .init(excludedEndpointPaths: ["/_status", "/1.0/features"])
        )

        XCTAssertEqual(state.filteredExchanges, [payment])
    }

    @MainActor
    func test_setExcludedEndpointPaths_normalizesAndDeduplicatesPatterns() async {
        let store = TestStore(initialState: Factory.makeAppState()) {
            UIReducer(environment: makeTestEnvironment())
        }

        await store.send(.setExcludedEndpointPaths([" /_STATUS ", "/_status", "/1.0/Features"])) {
            $0.filters.excludedEndpointPaths = ["/_status", "/1.0/features"]
        }
    }

    @MainActor
    func test_excludeEndpointPath_deduplicatesCaseInsensitively() async {
        let store = TestStore(
            initialState: Factory.makeAppState(filters: .init(excludedEndpointPaths: ["/_status"]))
        ) {
            UIReducer(environment: makeTestEnvironment())
        }

        await store.send(.excludeEndpointPath(" /_STATUS "))

        await store.send(.excludeEndpointPath(" /1.0/Features ")) {
            $0.filters.excludedEndpointPaths = ["/_status", "/1.0/features"]
        }
    }

    func test_textForResponseRaw_usesAvailableResponseBody() {
        let exchange = Factory.makeExchange(
            path: "/2.0/example/payment",
            responseBody: #"{"ok":true}"#
        )

        XCTAssertEqual(exchange.textFor(.response, tab: .raw), #"{"ok":true}"#)
    }

    // MARK: - Private Methods

    private func encodeAndDecode(state: AppState) throws -> AppState {
        let encodedState = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(AppState.self, from: encodedState)
    }

    private func makeTestEnvironment() -> AppEnvironment {
        AppEnvironment(
            appStateArchiver: NoOpAppStateArchiver(),
            pasteboard: .init(name: NSPasteboard.Name("AppStateTests-\(UUID().uuidString)")),
            urlOpener: { _ in }
        )
    }
}

// MARK: -

private struct NoOpAppStateArchiver: AppStateArchiver {
    func archiveAppState(_ state: AppState) {}
    func unarchiveAppState() -> AppState? { nil }
}

// MARK: -

private enum Factory {

    static func makeAppState(
        fixturesRepoPath: String = "~/foo/bar",
        exchanges: [Exchange] = [Exchanges.finalizedResponse],
        starredExchanges: Set<UUID> = [Exchanges.finalizedResponse.id],
        defaultResponsePolicy: ResponsePolicy = .alwaysAsk,
        rules: [Rule] = [Rules.proxy, Rules.alwaysAsk],
        responseFixtures: [Endpoint: [Fixture]] = [
            Endpoints.paymentHistoryJS: [Fixtures.paymentHistoryJS],
        ],
        selectedExchange: Exchange? = Exchanges.finalizedResponse,
        maxExchangesToKeep: Int = 200,
        filters: FilterCollection = .init(
            hideFailedRequests: false,
            hideSuccessfulRequests: false,
            searchText: ""
        ),
        enableJsonHighlighting: Bool = true,
        detailViewFontSize: CGFloat = 11.0,
        selectedRequestTab: ExchangeDetailTab = .body,
        selectedResponseTab: ExchangeDetailTab = .body,
        showFullURLs: Bool = false,
        showTimestamps: Bool = false,
        assumeProxyingEnabled: Bool = true,
        exchangeDetailPaneConfiguration: ExchangeDetailPaneConfiguration = .both,
        customResponsePolicies: [CustomResponsePolicy] = [CustomResponsePolicies.localHost]
    ) -> AppState {
        .init(
            fixturesRepoPath: fixturesRepoPath,
            exchanges: exchanges,
            starredExchanges: starredExchanges,
            defaultResponsePolicy: defaultResponsePolicy,
            rules: IdentifiedArrayOf(uniqueElements: rules),
            responseFixtures: responseFixtures,
            selectedExchange: selectedExchange,
            maxExchangesToKeep: maxExchangesToKeep,
            filters: filters,
            enableJsonHighlighting: enableJsonHighlighting,
            detailViewFontSize: detailViewFontSize,
            selectedRequestTab: selectedRequestTab,
            selectedResponseTab: selectedResponseTab,
            showFullURLs: showFullURLs,
            showTimestamps: showTimestamps,
            assumeProxyingEnabled: assumeProxyingEnabled,
            exchangeDetailPaneConfiguration: exchangeDetailPaneConfiguration,
            customResponsePolicies: IdentifiedArrayOf(uniqueElements: customResponsePolicies)
        )
    }

    enum Exchanges {
        static let pendingResponse = Exchange(
            request: request,
            rule: Rules.alwaysAsk,
            state: .pendingResponse(
                responseSink: ResponseSink(responseSender: { _ in }),
                errorMessage: nil
            )
        )

        static let sendingResponse = Exchange(
            request: request,
            rule: Rules.proxy,
            state: .sendingResponse(
                using: .proxy,
                responseSink: ResponseSink(responseSender: { _ in })
            )
        )

        static let finalizedResponse = Exchange(
            request: request,
            rule: Rules.proxy,
            state: .finalizedResponse(response, selectedPolicy: .proxy)
        )
    }

    static let request = Request(
        id: "test-request-id",
        url: URL(string: "https://api.example.com/2.0/example/endpoint")!,
        httpMethod: "POST",
        headers: ["foo": "bar"],
        timestamp: Date(timeIntervalSince1970: 1),
        humanReadableBody: "foo",
        rawBody: Data("foo".utf8)
    )

    static let response = HumanReadableResponse(
        requestID: request.id,
        headers: ["foo": "bar"],
        body: "{}",
        statusCode: 200
    )

    static func makeExchange(
        path: String,
        requestBody: String = "{}",
        responseBody: String = "{}"
    ) -> Exchange {
        let request = Request(
            id: UUID().uuidString,
            url: URL(string: "https://api.example.com\(path)")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(timeIntervalSince1970: 1),
            humanReadableBody: requestBody,
            rawBody: Data(requestBody.utf8)
        )
        let response = HumanReadableResponse(
            requestID: request.id,
            headers: ["Content-Type": "application/json"],
            body: responseBody,
            statusCode: 200
        )
        return Exchange(
            request: request,
            rule: Rules.proxy,
            state: .finalizedResponse(response, selectedPolicy: .proxy)
        )
    }

    enum Endpoints {
        static let syncEntities = Endpoint(path: "/2.0/example/sync-entities")
        static let paymentHistoryJS = Endpoint(path: "/scripts/payment-history.js")
    }

    enum Rules {
        static let proxy = Rule(endpoint: Endpoints.syncEntities, responsePolicy: .proxy)
        static let alwaysAsk = Rule(endpoint: Endpoints.paymentHistoryJS, responsePolicy: .alwaysAsk)
    }

    enum CustomResponsePolicies {
        static let localHost = CustomResponsePolicy(
            name: "Proxy to Local Host",
            value: .reroute()
        )
    }

    enum Fixtures {
        static let paymentHistoryJS = Fixture(
            kind: .text(contentType: "application/javascript"),
            url: URL(string: "file:///fixtures/scripts/payment-history.js")!
        )
    }
}
