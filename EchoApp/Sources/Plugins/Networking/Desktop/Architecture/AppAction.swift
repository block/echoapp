import AppKit
import CasePaths
import EchoPluginAPI
import Foundation
import IdentifiedCollections

/// Defines all actions that can be dispatched to modify the application state.
/// This is used to enforce a unidirectional data flow
/// i.e. the view dispatches an action which mutates the state of the app which causes the
/// view to render the updated state
@CasePathable
public enum AppAction {
    case lifecycle(LifecycleAction)
    case exchange(ExchangeAction)
    case load(LoadAction)
    case ui(UIAction)
}

// MARK: -

/// Actions related to lifecycle of the application
public enum LifecycleAction: Equatable {
    /// The app finished launching - perform setup.
    case appDidFinishLaunching

    /// The app is about to exit
    case appWillTerminate

    /// Save the app state to disk
    case saveAppState

    /// Reset all generated state and restore defaults
    case resetAppState
}

// MARK: -

/// Actions related to exchanges
public enum ExchangeAction: Equatable {
    /// Adds an exchange to internal storage
    case recordExchange(Exchange)

    /// Add a response to internal storage
    /// Note: the response's requestID must match a previously-recorded Request
    case recordResponse(HumanReadableResponse)

    /// The client encountered an error.
    case recordClientError(NetworkingPluginClientEvent.Error, requestID: String)

    /// The server encountered an error while processing a request.
    case recordServerError(String, requestID: String)

    /// Remove currently selected exchange from internal storage
    case clearSelected(Exchange)

    /// Remove all exchanges from internal storage
    case clearExchanges

    /// Updates the exchange in internal storage if the exchange exists
    case updateExchange(Exchange)

    /// Choose the response policy  for the selected exchange and use it to provide a response to the client
    case chooseResponsePolicy(Exchange, ResponsePolicy)

    /// Adds a new rule or updates the existing rule by ID
    case addOrUpdateRule(Rule)

    /// Change how rules are sorted in the UI
    case sortRules([KeyPathComparator<Rule>])

    /// Removes the provided rules from internal storage
    case removeRules(Set<Rule.ID>)

    /// Change how custom response policies are sorted in the UI
    case sortCustomResponsePolicies([KeyPathComparator<CustomResponsePolicy>])

    /// Adds a new custom response policy or updates the existing one by ID
    case addOrUpdateCustomResponsePolicy(CustomResponsePolicy)

    /// Removes the provided response policies from internal storage
    case removeCustomResponsePolicies(Set<CustomResponsePolicy.ID>)

    /// When the user taps "Copy" button, copies whatever content is below button
    case copyExchangeInformationToClipboard(ExchangeSection, Exchange)

    /// Updates the app state to reflect which section and detail tab (Headers, Body, Raw) the user has selected
    case exchangeTabTappedAt(ExchangeSection, ExchangeDetailTab)

    /// Updates the max number of exchanges
    case maxExchangesToKeepChanged(Int)
}

// MARK: -

/// An enum to represent which section an action is coming from
public enum ExchangeSection {
    /// The section where the request information resides
    case request

    /// The section where the response of the request resides
    case response
}

// MARK: -

/// Actions related to asynchronous data loading
public enum LoadAction {
    /// Load the list of fixtures that can be used to respond to each endpoint
    case loadResponseFixtures

    /// Loaded the list of fixtures that can be used with each endpoint in the fixtures repo path
    case loadedResponseFixtures([Endpoint: [Fixture]])
}

// MARK: -

public enum UIAction: Equatable {
    /// Perform a navigation action
    case navigate(NavigationAction)

    /// Sets the path used to load fixtures from disk
    case setFixturesRepoPath(String)

    /// Sent when the UIReducer changes the fixtures repo path.
    /// The parent reducer listens to this event and uses it to reload fixtures from disk.
    case didChangeFixturesRepoPath

    /// Sets the network exchange search text
    case setSearchText(String)

    /// Replaces endpoint path patterns that should be hidden from the list
    case setExcludedEndpointPaths([String])

    /// Adds an endpoint path pattern to the hidden list
    case excludeEndpointPath(String)

    /// Set the hideFailedRequests filter
    case hideFailedRequests(Bool)

    /// Set the hideSuccessfulRequests filter
    case hideSuccessfulRequests(Bool)

    /// Sets JSON highlighting. Off sets text to default black or white (depending on light/dark mode)
    case enableJsonHighlighting(Bool)

    /// Set the default response policy
    case setDefaultResponsePolicy(ResponsePolicy)

    /// Copy the request path to the user's clipboard
    case copyRequestPath(Request)

    /// Copy the request's full URL to the user's clipboard
    case copyRequestFullURL(Request)

    /// Copy the request as a cURL command to the user's clipboard
    case copyRequestAscURL(Request)
    
    /// Copy complete exchange information (request + response) to the user's clipboard
    case copyCompleteExchangeInfo(Exchange)

    /// Stars the exchange in the UI for easier parsing
    case starExchange(UUID)

    /// Save a response fixture for a specific endpoint
    case saveFixture(Endpoint, HumanReadableResponse)

    /// Change the Request & Response detail views font size
    case updateDetailViewFontSize(DetailViewFontSizeAction)

    /// Sets the user's preference for how the detail pane should be displayed
    case setExchangeDetailPaneConfiguration(ExchangeDetailPaneConfiguration)

    /// Open settings for a specific rule, showing the rules UI and focusing on the specified rule
    case openSettingsForRule(Rule?)
    
    /// Create a new rule for a specific endpoint and navigate to the rules settings
    case createRuleForEndpoint(Endpoint)


    /// Toggles State.showFullURLs
    case setShowFullURLs(Bool)

    /// Toggles State.showTimestamps
    case setShowTimestamps(Bool)
}

// MARK: -

extension UIAction {

    public enum NavigationAction: Equatable {
        /// Select the provided exchange in the UI, revealing information about the exchange in the detail view
        case selectExchange(Exchange)

        /// Select the previous exchange in the list
        case selectPreviousExchange

        /// Select the next exchange in the list
        case selectNextExchange

        /// Toggle showing the UI for editing Rules
        case showRules(Bool)
    }

    public enum DetailViewFontSizeAction: Equatable {
        /// Increase Detail Views content font size
        case increment

        /// Decrease Detail Views content font size
        case decrement

        /// Reset Detail Views content size to the default value
        case reset
    }

}
