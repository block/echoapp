import AppKit
import Foundation
import EchoPluginAPI
import IdentifiedCollections

/// Describes the state of the entire application.
public struct AppState: Equatable {

    // MARK: - Public Static Properties

    public static let defaultFixturesRepoPath = "~/Library/Application Support/Echo/PluginData/Networking/Fixtures"

    // MARK: - Public Properties

    public var fixturesRepoPath: String

    /// A list of client-server exchanges.
    /// Each exchange contains the request received from the client and
    /// the returned response (if one has been provided).
    public var exchanges: [Exchange]

    /// A list of client-server exchanges that have been starred by the user
    public var starredExchanges: Set<UUID>

    /// Describes how the plugin should respond to incoming requests
    public var defaultResponsePolicy: ResponsePolicy

    /// Contains response policies that should be used instead of `defaultResponsePolicy`, on a per-endpoint basis
    public var rules: IdentifiedArrayOf<Rule>

    /// Fixtures that can be used to respond to incoming requests
    public var responseFixtures: [Endpoint: [Fixture]]

    /// The maximum number of exchanges to keep.
    /// Older exchanges will be deleted automatically to stay within this limit.
    public var maxExchangesToKeep: Int

    /// When true, full URLs (including scheme and host) are shown in the UI.
    /// When false, only the path is shown
    public var showFullURLs: Bool

    /// When true, timestamps are shown in the UI for each network event.
    /// When false, timestamps are hidden
    public var showTimestamps: Bool

    // MARK: - Public Properties (UI State)

    public var selectedExchange: Exchange?
    public var filters: FilterCollection
    public var enableJsonHighlighting: Bool
    public var detailViewFontSize: CGFloat
    public var selectedRequestTab: ExchangeDetailTab
    public var selectedResponseTab: ExchangeDetailTab
    public var isShowingRuleSettings = false
    public var focusedRuleID: Rule.ID? = nil // nil means focus default
    public var exchangeDetailPaneConfiguration: ExchangeDetailPaneConfiguration
    public var customResponsePolicies: IdentifiedArrayOf<CustomResponsePolicy>

    /// When true, we can assume the client is proxying requests.
    /// When false, we can assume the client is operating in non-proxy/passive mode.
    public var assumeProxyingEnabled: Bool

    // MARK: - Life Cycle

    public init(
        fixturesRepoPath: String = Self.defaultFixturesRepoPath,
        exchanges: [Exchange] = [],
        starredExchanges: Set<UUID> = .init(),
        defaultResponsePolicy: ResponsePolicy = .proxy,
        rules: IdentifiedArrayOf<Rule> = [],
        responseFixtures: [Endpoint: [Fixture]] = [:],
        selectedExchange: Exchange? = nil,
        maxExchangesToKeep: Int = 150,
        filters: FilterCollection = .init(),
        enableJsonHighlighting: Bool = true,
        detailViewFontSize: CGFloat = NSFont.Fakelin.code.pointSize,
        selectedRequestTab: ExchangeDetailTab = .body,
        selectedResponseTab: ExchangeDetailTab = .body,
        showFullURLs: Bool = false,
        showTimestamps: Bool = false,
        assumeProxyingEnabled: Bool = true,
        exchangeDetailPaneConfiguration: ExchangeDetailPaneConfiguration = .both,
        customResponsePolicies: IdentifiedArrayOf<CustomResponsePolicy> = .init(
            uniqueElements: CustomResponsePolicy.defaults
        )
    ) {
        self.fixturesRepoPath = fixturesRepoPath
        self.exchanges = exchanges
        self.starredExchanges = starredExchanges
        self.defaultResponsePolicy = defaultResponsePolicy
        self.rules = rules
        self.responseFixtures = responseFixtures
        self.selectedExchange = selectedExchange
        self.maxExchangesToKeep = maxExchangesToKeep
        self.filters = filters
        self.enableJsonHighlighting = enableJsonHighlighting
        self.detailViewFontSize = detailViewFontSize
        self.selectedRequestTab = selectedRequestTab
        self.selectedResponseTab = selectedResponseTab
        self.showFullURLs = showFullURLs
        self.showTimestamps = showTimestamps
        self.assumeProxyingEnabled = assumeProxyingEnabled
        self.exchangeDetailPaneConfiguration = exchangeDetailPaneConfiguration
        self.customResponsePolicies = customResponsePolicies
    }
}

// MARK: -

extension AppState {

    var fixturesRepoURL: URL {
        URL(fileURLWithPath: (fixturesRepoPath as NSString).expandingTildeInPath)
    }

    var selectedExchangeIndex: Int? {
        if let selectedExchangeID = selectedExchange?.id {
            return exchanges.firstIndex(where: { $0.id == selectedExchangeID })
        }
        return nil
    }

    var filteredExchanges: [Exchange] {
        exchanges.filtered(using: filters)
    }

    var selectedExchangeIndexInFilteredExchanges: Int? {
        if let selectedExchangeID = selectedExchange?.id {
            return filteredExchanges.firstIndex(where: { $0.id == selectedExchangeID })
        }
        return nil
    }

    var defaultRuleResponsePolicies: [ResponsePolicy] {
        return [.alwaysAsk, .proxy] + sortedCustomResponsePolicies
    }

    /// Response policies which can be used to configure an **override** for _any_ endpoint (i.e. in the Rules editor), excluding fixtures.
    func overrideResponsePolicies(for endpoint: Endpoint) -> [ResponsePolicy] {
        [.alwaysAsk] + liveResponsePolicies(for: endpoint)
    }

    /// Response policies which can be used to respond to a **live request** for _any_ endpoint, excluding fixtures.
    func liveResponsePolicies(for endpoint: Endpoint) -> [ResponsePolicy] {
        return [.proxy] + sortedCustomResponsePolicies
    }

    var sortedCustomResponsePolicies: [ResponsePolicy] {
        customResponsePolicies
            .sorted { $0.name < $1.name }
            .map(ResponsePolicy.custom)
    }

    func fixtureResponsePolicies(for endpoint: Endpoint) -> [ResponsePolicy]? {
        if let fixtures = self.responseFixtures[endpoint], !fixtures.isEmpty {
            return fixtures.map(ResponsePolicy.fixture)
        } else {
            return nil
        }
    }
}

// MARK: -

/// Describes which panes to display in the Exchange detail view
public enum ExchangeDetailPaneConfiguration: String, Identifiable, Equatable, Codable, CaseIterable {
    case request = "Request"
    case response = "Response"
    case both = "Both"

    public var id: String {
        rawValue
    }

    var shouldShowRequest: Bool { self == .request || self == .both }
    var shouldShowResponse: Bool { self == .response || self == .both }
}

// MARK: -

/// Describes which information to display _within_ an Exchange detail view pane
public enum ExchangeDetailTab: String, CaseIterable, Equatable {
    case headers = "Headers"
    case body = "Body"
    case raw = "Raw"
}

// MARK: -

/// A collection of options used to curate the list of exchanges in the UI
public struct FilterCollection: Equatable, Codable {
    public var hideFailedRequests = false
    public var hideSuccessfulRequests = false
    public var searchText = ""
    public var excludedEndpointPaths: [String] = []

    public var endpointPath: String {
        get { searchText }
        set { searchText = newValue }
    }

    private enum CodingKeys: CodingKey {
        case hideFailedRequests
        case hideSuccessfulRequests
        case searchText
        // Legacy persisted key from when network search only matched endpoint paths.
        case endpointPath
        case excludedEndpointPaths
    }

    public init(
        hideFailedRequests: Bool = false,
        hideSuccessfulRequests: Bool = false,
        searchText: String = "",
        excludedEndpointPaths: [String] = []
    ) {
        self.hideFailedRequests = hideFailedRequests
        self.hideSuccessfulRequests = hideSuccessfulRequests
        self.searchText = searchText
        self.excludedEndpointPaths = excludedEndpointPaths.normalizedEndpointPathPatterns()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hideFailedRequests: try container.decode(Bool.self, forKey: .hideFailedRequests),
            hideSuccessfulRequests: try container.decode(Bool.self, forKey: .hideSuccessfulRequests),
            searchText: try container.decodeIfPresent(String.self, forKey: .searchText)
                ?? container.decodeIfPresent(String.self, forKey: .endpointPath)
                ?? "",
            excludedEndpointPaths: try container.decodeIfPresent(
                [String].self,
                forKey: .excludedEndpointPaths
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hideFailedRequests, forKey: .hideFailedRequests)
        try container.encode(hideSuccessfulRequests, forKey: .hideSuccessfulRequests)
        try container.encode(searchText, forKey: .searchText)
        try container.encode(excludedEndpointPaths, forKey: .excludedEndpointPaths)
    }
}

extension Array where Element == String {

    func normalizedEndpointPathPatterns() -> [String] {
        var seen: Set<String> = []
        return compactMap { path in
            let normalized = path.normalizedEndpointPathPattern
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
}

extension String {

    var normalizedEndpointPathPattern: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Array where Element == Exchange {

    func filtered(using filters: FilterCollection) -> [Element] {
        let normalizedSearch = filters.normalizedSearchText
        let excludedPaths = filters.excludedEndpointPaths
        return filter { exchange in
            guard exchange.matchesSearchText(normalizedSearch) else { return false }
            guard !exchange.matchesAnyEndpointPath(excludedPaths) else { return false }

            switch exchange.state {
            case .waitingForClientProvidedResponse, .pendingResponse, .sendingResponse:
                return true

            case let .finalizedResponse(response, _):
                if filters.hideFailedRequests && !response.isSuccessful { return false }
                if filters.hideSuccessfulRequests && response.isSuccessful { return false }
            }
            return true
        }
    }

}

extension FilterCollection {

    fileprivate var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Exchange {

    fileprivate func matchesAnyEndpointPath(_ excludedPaths: [String]) -> Bool {
        guard !excludedPaths.isEmpty else { return false }

        let normalizedPath = request.endpoint.path.lowercased()
        return excludedPaths.contains { normalizedPath.contains($0) }
    }

    fileprivate func matchesSearchText(_ normalizedSearch: String) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }

        if request.url.absoluteString.containsSearchText(normalizedSearch)
            || request.endpoint.path.containsSearchText(normalizedSearch)
            || request.httpMethod.containsSearchText(normalizedSearch)
            || request.headers.containsSearchText(normalizedSearch)
            || request.humanReadableBody.containsSearchText(normalizedSearch)
            || state.description.containsSearchText(normalizedSearch) {
            return true
        }

        if let response {
            return response.headers.containsSearchText(normalizedSearch)
                || response.body.containsSearchText(normalizedSearch)
                || "\(response.statusCode)".containsSearchText(normalizedSearch)
        }

        return false
    }
}

extension Dictionary where Key == String, Value == String {

    fileprivate func containsSearchText(_ searchText: String) -> Bool {
        contains { key, value in
            key.containsSearchText(searchText) || value.containsSearchText(searchText)
        }
    }
}

extension String {

    fileprivate func containsSearchText(_ searchText: String) -> Bool {
        range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

// MARK: - Codable

extension AppState: Codable {

    enum CodingKeys: CodingKey {
        case fixturesRepoPath
        case exchanges
        case starredExchanges
        case defaultResponsePolicy
        case maxExchangesToKeep
        case rules
        case responseFixtures
        case selectedExchange
        case filters
        case enableJsonHighlighting
        case detailViewFontSize
        case assumeProxyingEnabled
        case exchangeDetailPaneConfiguration
        case customResponsePolicies
        case showFullURLs
        case showTimestamps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fixturesRepoPath: try container.decodeIfPresent(
                String.self,
                forKey: .fixturesRepoPath
            ) ?? AppState.defaultFixturesRepoPath,
            exchanges: try container.decode([Exchange].self, forKey: .exchanges),
            starredExchanges: try container.decode(Set<UUID>.self, forKey: .starredExchanges),
            defaultResponsePolicy: try container.decode(ResponsePolicy.self, forKey: .defaultResponsePolicy),
            rules: try container.decodeIfPresent(IdentifiedArrayOf<Rule>.self, forKey: .rules) ?? [],
            responseFixtures: try container.decode(
                [Endpoint: [Fixture]].self,
                forKey: .responseFixtures
            ),
            selectedExchange: try container.decodeIfPresent(Exchange.self, forKey: .selectedExchange),
            maxExchangesToKeep: try container.decode(Int.self, forKey: .maxExchangesToKeep),
            filters: try container.decode(FilterCollection.self, forKey: .filters),
            enableJsonHighlighting: try container.decodeIfPresent(
                Bool.self,
                forKey: .enableJsonHighlighting
            ) ?? true,
            detailViewFontSize: try container.decodeIfPresent(CGFloat.self, forKey: .detailViewFontSize)
            ?? NSFont.Fakelin.code.pointSize,
            showFullURLs: try container.decodeIfPresent(Bool.self, forKey: .showFullURLs) ?? false,
            showTimestamps: try container.decodeIfPresent(Bool.self, forKey: .showTimestamps) ?? false,
            assumeProxyingEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .assumeProxyingEnabled
            ) ?? true,
            exchangeDetailPaneConfiguration: try container.decodeIfPresent(
                ExchangeDetailPaneConfiguration.self,
                forKey: .exchangeDetailPaneConfiguration
            ) ?? .both,
            customResponsePolicies: try container.decodeIfPresent(
                IdentifiedArrayOf<CustomResponsePolicy>.self,
                forKey: .customResponsePolicies
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fixturesRepoPath, forKey: .fixturesRepoPath)

        // Only encode completed exchanges
        try container.encode(exchanges.filter({ $0.response != nil }), forKey: .exchanges)
        try container.encode(starredExchanges, forKey: .starredExchanges)
        try? container.encode(selectedExchange, forKey: .selectedExchange)

        try container.encode(defaultResponsePolicy, forKey: .defaultResponsePolicy)
        try container.encode(rules, forKey: .rules)
        try container.encode(responseFixtures, forKey: .responseFixtures)
        try container.encode(maxExchangesToKeep, forKey: .maxExchangesToKeep)
        try container.encode(filters, forKey: .filters)
        try container.encode(enableJsonHighlighting, forKey: .enableJsonHighlighting)
        try container.encode(detailViewFontSize, forKey: .detailViewFontSize)
        try container.encode(showFullURLs, forKey: .showFullURLs)
        try container.encode(showTimestamps, forKey: .showTimestamps)
        try container.encode(assumeProxyingEnabled, forKey: .assumeProxyingEnabled)
        try container.encode(exchangeDetailPaneConfiguration, forKey: .exchangeDetailPaneConfiguration)
        try container.encode(customResponsePolicies, forKey: .customResponsePolicies)
    }
}
