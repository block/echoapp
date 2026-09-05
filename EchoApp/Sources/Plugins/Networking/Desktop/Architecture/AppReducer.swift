import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import EchoPluginAPI

/// Modifies app state based on lifecycle actions
struct LifecycleReducer: Reducer {
    typealias State = AppState
    typealias Action = LifecycleAction

    let environment: AppEnvironment

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .appDidFinishLaunching:
            if let savedState = environment.appStateArchiver.unarchiveAppState() {
                state = savedState
            }
            return .none

        case .appWillTerminate:
            return Effect.send(.saveAppState)

        case .saveAppState:
            environment.appStateArchiver.archiveAppState(state)
            return .none

        case .resetAppState:
            state = AppState()
            return .none
        }
    }
}

/// Modifies app state based on exchange actions
struct ExchangeReducer: Reducer {
    typealias State = AppState
    typealias Action = ExchangeAction

    let environment: AppEnvironment

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func reduce(into state: inout AppState, action: ExchangeAction) -> Effect<ExchangeAction> {
        switch action {
        case var .recordExchange(exchange):
            let rule: Rule? = state.rules.first(where: { $0.endpoint.matches(exchange.request.endpoint) })
            if let rule {
                // Add rule to exchange for rendering in UI
                exchange.rule = rule
            }
            state.exchanges.append(exchange)

            // Trim old exchanges if we're over the limit
            if state.exchanges.count > state.maxExchangesToKeep {
                state.exchanges.removeFirst(state.exchanges.count - state.maxExchangesToKeep)

                // Add back the selected exchange if it was trimmed
                if let selectedExchange = state.selectedExchange, !state.exchanges.contains(selectedExchange) {
                    state.exchanges.insert(selectedExchange, at: 0)
                }
            }

            guard case .pendingResponse = exchange.state else {
                // This exchange isn't pending a response from Echo. This means the client is operating in
                // Non-Proxy Mode and will report the response. There's nothing left for Echo to do for this exchange.
                state.assumeProxyingEnabled = false
                return .none
            }
            state.assumeProxyingEnabled = true

            // Automatically respond if a custom policy has been registered for this request path.
            // Otherwise, use the default policy
            if let rule = rule {
                return Effect.send(.chooseResponsePolicy(exchange, rule.responsePolicy))
            } else {
                let defaultResponsePolicy = state.defaultResponsePolicy
                return Effect.send(.chooseResponsePolicy(exchange, defaultResponsePolicy))
            }

        case let .recordResponse(response):
            guard var exchange = state.exchanges.first(where: { exchange in
                exchange.request.id == response.requestID
            }) else {
                print("Ignoring response -- no request with id \(response.requestID)")
                return .none
            }
            // Extract response policy information from the current state
            // - `selectedPolicy`: The policy that was actually chosen for the final response
            //   (may be different from initial if user had to choose when initial was .alwaysAsk)
            // Extract the policy that was used for this response
            let selectedPolicy: ResponsePolicy
            switch exchange.state {
            case .sendingResponse(let policy, _):
                selectedPolicy = policy
            default:
                // For other states, use default policy
                selectedPolicy = .proxy
            }
            exchange.state = .finalizedResponse(response, selectedPolicy: selectedPolicy)
            return Effect.send(.updateExchange(exchange))

        case let .recordClientError(error, requestID):
            guard var exchange = state.exchanges.first(where: { exchange in
                exchange.request.id == requestID
            }) else {
                print("Ignoring client error; no request with id \(requestID)")
                return .none
            }
            switch error {
            case let .failedToParseProposedHumanReadableResponse(errorReason):
                guard case let .sendingResponse(_, responseSink) = exchange.state else {
                    // The client has already finalized the response so they can't retry.
                    // This can happen if the request times out while the user is choosing a response.
                    print("Ignoring client error; request with id \(requestID) has already been finalized")
                    return .none
                }
                // Move the exchange back into the `pendingResponse` state so the user can try again.
                exchange.state = .pendingResponse(responseSink: responseSink, errorMessage: errorReason)
                return Effect.send(.updateExchange(exchange))
            }

        case let .recordServerError(errorMessage, requestID):
            guard var exchange = state.exchanges.first(where: { exchange in
                exchange.request.id == requestID
            }) else {
                print("Ignoring server error; no request with id \(requestID)")
                return .none
            }
            guard case let .sendingResponse(_, responseSink) = exchange.state else {
                // The exchange is no longer in a state where we can show an error.
                // This can happen if the request times out or the exchange is already finalized.
                print("Ignoring server error; request with id \(requestID) is in state: \(exchange.state)")
                return .none
            }
            // Move the exchange back into the `pendingResponse` state so the user can try again.
            exchange.state = .pendingResponse(responseSink: responseSink, errorMessage: errorMessage)
            return Effect.send(.updateExchange(exchange))

        case let .clearSelected(exchange):
            if let index = state.exchanges.firstIndex(of: exchange) {
                state.exchanges.remove(at: index)
            }
            return .none

        case .clearExchanges:
            let clearedExchanges = state.exchanges
            state.exchanges = []
            state.selectedExchange = nil
            return cleanUpClearedExchanges(clearedExchanges)

        case let .updateExchange(updatedExchange):
            state.exchanges = state.exchanges.map { exchange in
                (exchange.id == updatedExchange.id) ? updatedExchange : exchange
            }
            // Make sure our selectedExchange also stays up to date
            if updatedExchange.id == state.selectedExchange?.id {
                state.selectedExchange = updatedExchange
            }
            return .none

        case let .chooseResponsePolicy(exchange, responsePolicy):
            if responsePolicy == .alwaysAsk {
                // Nothing to do yet.
                return .none
            } else {
                return sendResponseToClient(
                    exchange: exchange,
                    responsePolicy: responsePolicy,
                    fixturesRepoURL: state.fixturesRepoURL,
                    environment: environment
                )
            }

        case let .addOrUpdateRule(rule):
            state.rules.updateOrAppend(rule)
            updateExistingExchangesForRule(rule, in: &state.exchanges)
            return .none

        case let .sortRules(sortOrder):
            state.rules.sort(using: sortOrder)
            return .none

        case let .removeRules(ruleIDs):
            for id in ruleIDs {
                state.rules.remove(id: id)
            }
            removeRulesFromExistingExchanges(ruleIDs, in: &state.exchanges)
            return .none

        case let .addOrUpdateCustomResponsePolicy(policy):
            state.customResponsePolicies.updateOrAppend(policy)

            // Update any rules that reference the updated policy
            for rule in state.rules where rule.responsePolicy.id == ResponsePolicy.custom(policy).id {
                state.rules[id: rule.id]?.responsePolicy = .custom(policy)
            }
            if state.defaultResponsePolicy.id == ResponsePolicy.custom(policy).id {
                state.defaultResponsePolicy = .custom(policy)
            }
            return .none

        case let .sortCustomResponsePolicies(sortOrder):
            state.customResponsePolicies.sort(using: sortOrder)
            return .none

        case let .removeCustomResponsePolicies(policyIDs):
            var removedPolicies: Set<ResponsePolicy> = []

            for id in policyIDs {
                if let removedPolicy = state.customResponsePolicies.remove(id: id) {
                    removedPolicies.insert(.custom(removedPolicy))
                }
            }

            // Update any rules that reference the removed policies
            for rule in state.rules where removedPolicies.contains(rule.responsePolicy) {
                state.rules[id: rule.id]?.responsePolicy = .alwaysAsk
            }
            if removedPolicies.contains(state.defaultResponsePolicy) {
                state.defaultResponsePolicy = .alwaysAsk
            }
            return .none

        case let .copyExchangeInformationToClipboard(exchangeSection, exchange):
            let stringForPasteboard: String? = {
                switch exchangeSection {
                case .request:
                    exchange.textFor(exchangeSection, tab: state.selectedRequestTab)
                case .response:
                    exchange.textFor(exchangeSection, tab: state.selectedResponseTab)
                }
            }()

            if let stringForPasteboard {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(stringForPasteboard, forType: .string)
            }
            return .none
        case let .exchangeTabTappedAt(exchangeSection, exchangeTab):
            switch exchangeSection {
            case .request:
                state.selectedRequestTab = exchangeTab
            case .response:
                state.selectedResponseTab = exchangeTab
            }
            return .none

        case let .maxExchangesToKeepChanged(maxCount):
            state.maxExchangesToKeep = maxCount
            return .none
        }
    }
}

// Modifies app state based on load actions
struct LoadReducer: Reducer {
    typealias State = AppState
    typealias Action = LoadAction

    let environment: AppEnvironment

    func reduce(into state: inout AppState, action: LoadAction) -> Effect<LoadAction> {
        switch action {
        case .loadResponseFixtures:
            return loadResponseFixtures(
                fromFixturesRepoDirectory: state.fixturesRepoURL,
                environment: environment
            )

        case let .loadedResponseFixtures(fixtures):
            state.responseFixtures = fixtures
            return .none
        }
    }
}

// Modifies app state based on UI actions
struct UIReducer: Reducer {
    typealias State = AppState
    typealias Action = UIAction

    let environment: AppEnvironment

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reduce(into state: inout AppState, action: UIAction) -> Effect<UIAction> {
        switch action {

        case let .setFixturesRepoPath(path):
            if path != state.fixturesRepoPath {
                state.fixturesRepoPath = path
                return .send(.didChangeFixturesRepoPath)
            }
            return .none

        case .didChangeFixturesRepoPath:
            // Implemented by parent reducer
            return .none

        case let .setSearchText(text):
            state.filters.searchText = text
            return .none

        case let .setExcludedEndpointPaths(paths):
            state.filters.excludedEndpointPaths = paths.normalizedEndpointPathPatterns()
            return .none

        case let .excludeEndpointPath(path):
            let normalizedPath = path.normalizedEndpointPathPattern
            guard !normalizedPath.isEmpty else { return .none }
            if !state.filters.excludedEndpointPaths.contains(normalizedPath) {
                state.filters.excludedEndpointPaths.append(normalizedPath)
            }
            return .none

        case let .hideFailedRequests(hideFailedRequests):
            state.filters.hideFailedRequests = hideFailedRequests
            return .none

        case let .hideSuccessfulRequests(hideSuccessfulRequests):
            state.filters.hideSuccessfulRequests = hideSuccessfulRequests
            return .none

        case let .enableJsonHighlighting(enableJsonHighlighting):
            state.enableJsonHighlighting = enableJsonHighlighting
            return .none

        case let .setDefaultResponsePolicy(defaultResponsePolicy):
            state.defaultResponsePolicy = defaultResponsePolicy
            return .none

        case let .copyRequestPath(request):
            return .run { _ in
                environment.pasteboard.clearContents()
                environment.pasteboard.setString(request.endpoint.path, forType: .string)
            }

        case let .copyRequestFullURL(request):
            return .run { _ in
                environment.pasteboard.clearContents()
                environment.pasteboard.setString(request.url.absoluteString, forType: .string)
            }

        case let .copyRequestAscURL(request):
            return .run { _ in
                environment.pasteboard.clearContents()
                environment.pasteboard.setString(request.asCurlCommand(), forType: .string)
            }
        
        case let .copyCompleteExchangeInfo(exchange):
            return .run { _ in
                environment.pasteboard.clearContents()
                environment.pasteboard.setString(exchange.completeInformation(), forType: .string)
            }

        case let .starExchange(id):
            if let index = state.starredExchanges.firstIndex(of: id) {
                state.starredExchanges.remove(at: index)
            } else {
                state.starredExchanges.insert(id)
            }
            return .none

        case .saveFixture:
            // Handled in the main AppReducer
            return .none

        case let .updateDetailViewFontSize(action):
            state.detailViewFontSize = adjustDetailViewFontSize(baseSize: state.detailViewFontSize, action: action)
            return .none

        case let .setExchangeDetailPaneConfiguration(configuration):
            state.exchangeDetailPaneConfiguration = configuration
            return .none

        case let .openSettingsForRule(rule):
            state.isShowingRuleSettings = true
            state.focusedRuleID = rule?.id
            return .none

        case let .setShowFullURLs(showFullURLs):
            state.showFullURLs = showFullURLs
            return .none

        case let .setShowTimestamps(showTimestamps):
            state.showTimestamps = showTimestamps
            return .none

        case let .createRuleForEndpoint(endpoint):
            // Create a new rule for the endpoint
            let newRule = Rule(
                id: UUID(),
                endpoint: endpoint,
                responsePolicy: state.defaultResponsePolicy
            )
            state.rules.append(newRule)
            updateExistingExchangesForRule(newRule, in: &state.exchanges)
            // Navigate to rules settings and focus on the new rule
            state.isShowingRuleSettings = true
            state.focusedRuleID = newRule.id
            return .none

        case let .navigate(navigateAction):
            switch navigateAction {
            case let .selectExchange(exchange):
                state.selectedExchange = exchange
                return .none

            case .selectPreviousExchange:
                guard let selectedIndex = state.selectedExchangeIndexInFilteredExchanges else {
                    return .none
                }
                let newSelectedIndex = max(selectedIndex - 1, 0)
                return .send(.navigate(.selectExchange(state.filteredExchanges[newSelectedIndex])))

            case .selectNextExchange:
                guard let selectedIndex = state.selectedExchangeIndexInFilteredExchanges else {
                    return .none
                }
                let newSelectedIndex = min(state.filteredExchanges.count - 1, selectedIndex + 1)
                return .send(.navigate(.selectExchange(state.filteredExchanges[newSelectedIndex])))

            case let .showRules(show):
                state.isShowingRuleSettings = show
                return .none
            }
        }
    }
}

struct AppReducer: Reducer {
    typealias State = AppState
    typealias Action = AppAction

    let environment: AppEnvironment

    var body: some Reducer<State, Action> {
        Scope(state: \.self, action: \.lifecycle) {
            LifecycleReducer(environment: environment)
        }
        Scope(state: \.self, action: \.exchange) {
            ExchangeReducer(environment: environment)
        }
        Scope(state: \.self, action: \.load) {
            LoadReducer(environment: environment)
        }
        Scope(state: \.self, action: \.ui) {
            UIReducer(environment: environment)
        }
        Reduce { state, action in
            switch action {
                // Keep known fixtures up to date
            case .lifecycle(.appDidFinishLaunching),
                    .ui(.didChangeFixturesRepoPath),
                    .ui(.navigate(.showRules)):
                return .send(.load(.loadResponseFixtures))

            case .load(.loadedResponseFixtures):
                validateFixtureBasedRules(state: &state)
                return .none
            
            case let .ui(.saveFixture(endpoint, response)):
                let defaultSaveDirectory = state.fixturesRepoURL
                    .appendingPathComponent(endpoint.path)
                    .standardizedFileURL
                return saveResponseToFile(response, endpoint: endpoint, defaultSaveDirectory: defaultSaveDirectory, environment: environment)

            default:
                return .none
            }
        }
    }

}

/// Updates existing exchanges that match the given rule's endpoint
private func updateExistingExchangesForRule(_ rule: Rule, in exchanges: inout [Exchange]) {
    for i in exchanges.indices {
        if exchanges[i].request.endpoint.matches(rule.endpoint) {
            exchanges[i].rule = rule
        }
    }
}

/// Removes rules from existing exchanges that no longer have a matching rule
private func removeRulesFromExistingExchanges(_ ruleIDs: Set<Rule.ID>, in exchanges: inout [Exchange]) {
    for i in exchanges.indices {
        if let exchangeRule = exchanges[i].rule,
           ruleIDs.contains(exchangeRule.id) {
            exchanges[i].rule = nil
        }
    }
}

/// Update any rules that use fixtures that no longer exist in the fixture repo
private func validateFixtureBasedRules(state: inout AppState) {
    let fixtureIDs = state.responseFixtures.lazy.flatMap { _, fixtures in
        fixtures.lazy.map(\.id)
    }
    for rule in state.rules {
        if case let .fixture(fixture) = rule.responsePolicy, !fixtureIDs.contains(fixture.id) {
            // Reset the response policy to .alwaysAsk since the fixture no longer exists
            state.rules[id: rule.id]?.responsePolicy = .alwaysAsk
        }
    }
}

/// Returns a side effect used to clean up exchanges that have been cleared
private func cleanUpClearedExchanges(_ exchanges: [Exchange]) -> Effect<ExchangeAction> {
    .concatenate(
        exchanges.reduce([]) { effects, exchange in
            if case .pendingResponse = exchange.state {
                // This exchange was cleared while the client was waiting for a response. Return a 500.
                return effects + [Effect.send(.chooseResponsePolicy(exchange, .custom(.internalServerError)))]
            } else {
                return effects
            }
        }
    )
}

// swiftlint:disable function_body_length
/// Returns a side effect used to generate and send an HTTP response to the client
/// according to the provided response policy.
private func sendResponseToClient(
    exchange: Exchange,
    responsePolicy: ResponsePolicy,
    fixturesRepoURL: URL,
    environment: AppEnvironment
) -> Effect<ExchangeAction> {

    guard case let .pendingResponse(responseSink, _) = exchange.state else {
        fatalError("Cannot send a response to the client from the \(exchange.state) state")
    }

    var mutableExchange = exchange
    mutableExchange.state = .sendingResponse(using: responsePolicy, responseSink: responseSink)
    let updatedExchange = mutableExchange

    // Update the exchange so the model is up to date while we're sending a response to the client
    let updateExchangeEffect = Effect<ExchangeAction>.send(.updateExchange(updatedExchange))

    // Send the response to the client.
    // We'll update thee exchange again when the client sends the finalized response.
    let sendResponseToClientEffect = Effect<ExchangeAction>.run { send in
        switch responsePolicy {
        case .alwaysAsk:
            fatalError("Should not be trying to send a response using the 'alwaysAsk' policy.")

        case let .fixture(fixture):
            responseSink.send(fixture, requestID: exchange.request.id)

        case let .custom(customPolicy):
            responseSink.sendCustomResponsePolicy(customPolicy, request: exchange.request)

        case .proxy:
            responseSink.proxyRequest(updatedExchange.request, replacementBaseURL: nil)
        }
    }

    return .concatenate(updateExchangeEffect, sendResponseToClientEffect)
}
// swiftlint:enable function_body_length

/// Returns a side effect that asynchronously loads fixtures that are appropriate for this request.
private func loadResponseFixtures(
    fromFixturesRepoDirectory fixturesRepoDirectory: URL,
    environment: AppEnvironment
) -> Effect<LoadAction> {
    .run(priority: .userInitiated) { send in
        let responseFixtures = environment.fixturesRepo.loadFixtures(
            fromFixturesRepoDirectory: fixturesRepoDirectory
        )
        await send(.loadedResponseFixtures(responseFixtures))
    }
}

/// Returns a side effect which prompts the user to save a new json fixture to their filesystem
private func saveResponseToFile(
    _ response: HumanReadableResponse,
    endpoint: Endpoint,
    defaultSaveDirectory: URL,
    environment: AppEnvironment
) -> Effect<AppAction> {
    .run { @MainActor send in
        // Create the directory structure if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: defaultSaveDirectory.path) {
            do {
                try fileManager.createDirectory(at: defaultSaveDirectory, withIntermediateDirectories: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to Create Directory"
                alert.informativeText = "Could not create directory at \(defaultSaveDirectory.path)\n\nError: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
        }
        
        // Prompt for filename using an alert with text input
        let alert = NSAlert()
        alert.messageText = "Save Fixture"
        alert.informativeText = "Enter a filename for the fixture:\n\nIt will be saved to:\n\(defaultSaveDirectory.path)"
        alert.alertStyle = .informational
        
        // Create text field for filename input
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "fixture.json"
        textField.placeholderString = "filename.json"
        alert.accessoryView = textField
        
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        // Set the text field as first responder so it's focused
        alert.window.initialFirstResponder = textField
        
        // Select all text in the field for easy editing
        DispatchQueue.main.async {
            textField.currentEditor()?.selectAll(nil)
        }
        
        let modalResponse = alert.runModal()
        guard modalResponse == .alertFirstButtonReturn else {
            // User canceled
            return
        }
        
        var filename = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure filename is not empty
        guard !filename.isEmpty else {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Invalid Filename"
            errorAlert.informativeText = "Please provide a valid filename."
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
            return
        }
        
        // Add .json extension if not present
        if !filename.hasSuffix(".json") {
            filename += ".json"
        }
        
        let fileURL = defaultSaveDirectory.appendingPathComponent(filename)
        
        do {
            try response.body.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Open the saved file in the default editor
            NSWorkspace.shared.open(fileURL)
            
            // Create a fixture object for the saved file
            let fixture = Fixture(
                kind: .text(contentType: "application/json"),
                url: fileURL
            )
            
            // Create a rule for this endpoint with the new fixture
            let rule = Rule(
                endpoint: endpoint,
                responsePolicy: .fixture(fixture)
            )
            
            // Add the rule to the app state
            send(.exchange(.addOrUpdateRule(rule)))
            
            // Reload fixtures so the new fixture appears in the UI
            send(.load(.loadResponseFixtures))
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Failed to Save Fixture"
            errorAlert.informativeText = "Could not save fixture to \(fileURL.path)\n\nError: \(error.localizedDescription)"
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
        }
    }
}

private func adjustDetailViewFontSize(baseSize: CGFloat, action: UIAction.DetailViewFontSizeAction) -> CGFloat {

    let intervalAmount: CGFloat = 2.0

    switch action {
    case .increment:
        return min(baseSize + intervalAmount, 40.0)

    case .decrement:
        return max(5.0, baseSize - intervalAmount)

    case .reset:
        return NSFont.Fakelin.code.pointSize
    }
}
