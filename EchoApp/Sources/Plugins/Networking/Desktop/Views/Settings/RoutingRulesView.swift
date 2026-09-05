import AppKit
import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

struct RoutingRulesView: View {
    let store: Store<AppState, AppAction>
    let focusedRuleID: Rule.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RulesDisabledView(store: store)

            DefaultRuleView(store: store, isFocused: focusedRuleID == nil)

            Divider()

            Text("Overrides")
                .font(.headline)
            RuleOverridesView(store: store, focusedRuleID: focusedRuleID)

            Divider()

            Text("Custom Responses")
                .font(.headline)
                .help("Custom responses can be used to build more complex rules")
            ManageCustomResponsePoliciesView(store: store)

            Divider()

            Text("Fixtures Directory")
                .font(.headline)
                .help(
                    """
                    Fixtures are human-readable responses (e.g. .json files) that can be used to respond to incoming requests.
                    Fixture files should be placed in a directory matching the endpoint they are intended to be used with.
                    For example: A fixture `login-success.json` intended to be used with the endpoint `/app/login` should be
                    stored at `{fixtures_repo}/app/login/login-success.json`.
                    """
                )
            FixturesView(store: store)
        }
        .navigationTitle("Network Monitor")
        .padding(.vertical)
        .padding(.horizontal, 16)
    }
}

// MARK: -

struct RulesDisabledView: View {
    let store: Store<AppState, AppAction>

    var body: some View {
        WithViewStore(store, observe: \.assumeProxyingEnabled) { viewStore in
            if !viewStore.state {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.primary)

                    Text("Rules only apply when the client is proxying requests. You may need to update your client.")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.4))
                )
            }
        }
    }
}

// MARK: -

struct DefaultRuleView: View {
    let store: Store<AppState, AppAction>
    let isFocused: Bool

    @FocusState private var pickerFocused: Bool

    var body: some View {
        HStack {
            Text("Default Rule")
                .font(.headline)
                .help("This rule applies when there are no matching overrides")
            picker()
        }
        .onAppear {
            if isFocused {
                pickerFocused = true
            }
        }
    }

    private func picker() -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            Picker(
                "",
                selection: viewStore.binding(
                    get: \.defaultResponsePolicy,
                    send: { .ui(.setDefaultResponsePolicy($0)) }
                )
            ) {
                ForEach(viewStore.defaultRuleResponsePolicies, id: \.name) { policy in
                    Text(policy.name)
                        .padding()
                        .tag(policy)
                }
            }
            .buttonStyle(.borderless)
            .labelsHidden()
            .focused($pickerFocused)
        }
    }
}

// MARK: -

struct RuleOverridesView: View {
    let store: Store<AppState, AppAction>
    let focusedRuleID: Rule.ID?

    // MARK: - Private Properties

    @State private var selectedRuleIDs: Set<Rule.ID> = []

    @State private var sortOrder: [KeyPathComparator<Rule>] = [
        .init(\.endpoint.path, order: .forward),
        .init(\.responsePolicy.name, order: .forward),
    ]

    /// When populated, the user is editing the endpoint for this rule
    @FocusState private var focusedRule: Rule.ID?

    // MARK: - View

    var body: some View {
        WithViewStore(store, observe: \.self) { viewStore in
            ScrollViewReader { scrollView in
                VStack(spacing: 0) {
                    table()
                    footerBar()
                }
                .onAppear {
                    if let id = focusedRuleID {
                        focusedRule = id
                        DispatchQueue.main.async {
                            withAnimation {
                                scrollView.scrollTo(id)
                            }
                        }
                    }
                }
                .onChange(of: sortOrder, initial: true) {
                    sortAndAutoScroll(scrollView: scrollView)
                }
                .onChange(of: viewStore.rules) {
                    sortAndAutoScroll(scrollView: scrollView)
                }
                .onChange(of: focusedRule) {
                    sortAndAutoScroll(scrollView: scrollView)
                    removeDuplicateRules(viewStore.rules)
                }
                .onChange(of: selectedRuleIDs) {
                    sortAndAutoScroll(scrollView: scrollView)
                }
                .onDeleteCommand {
                    viewStore.send(.exchange(.removeRules(selectedRuleIDs)))
                }
            }
        }
    }

    // MARK: - Private Methods (Subviews)

    private func table() -> some View {
        WithViewStore(store, observe: \.rules) { viewStore in
            Table(
                viewStore.state,
                selection: $selectedRuleIDs,
                sortOrder: $sortOrder,
                columns: {
                    TableColumn("Endpoint", value: \.endpoint.path, content: endpointColumnContent)
                    TableColumn("Response", value: \.responsePolicy.name, content: responseColumnContent)
                        .width(min: 220, max: 320)
                }
            )
            .tableStyle(.inset)
        }
    }

    private func endpointColumnContent(for rule: Rule) -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            TextField("", text: viewStore.endpointPathBinding(for: rule))
                .font(.system(size: 12, design: .monospaced))
                .focused($focusedRule, equals: rule.id)
                .onSubmit { focusedRule = nil }
                .withTextInputSuggestions(viewStore.textSuggestions(for: rule))
        }
    }

    private func responseColumnContent(for rule: Rule) -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            Menu {
                Section {
                    ForEach(viewStore.state.overrideResponsePolicies(for: rule.endpoint)) { policy in
                        Button(policy.name) {
                            viewStore.send(.exchange(.addOrUpdateRule(
                                Rule(id: rule.id, endpoint: rule.endpoint, responsePolicy: policy)
                            )))
                        }
                    }
                }
                if let fixturePolicies = viewStore.state.fixtureResponsePolicies(for: rule.endpoint) {
                    Section("Fixtures") {
                        ForEach(fixturePolicies) { fixturePolicy in
                            Button(fixturePolicy.name) {
                                viewStore.send(.exchange(.addOrUpdateRule(
                                    Rule(id: rule.id, endpoint: rule.endpoint, responsePolicy: fixturePolicy)
                                )))
                            }
                        }
                    }
                }
                Section {
                    Button {
                        createNewFixtureForRule(rule: rule, fixturesRepoPath: viewStore.fixturesRepoPath, viewStore: viewStore)
                    } label: {
                        Label("Create New Fixture", systemImage: "plus.circle.fill")
                    }
                }
            } label: {
                Text(rule.responsePolicy.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .contextMenu {
                if case let .fixture(fixture) = rule.responsePolicy {
                    Button {
                        NSWorkspace.shared.open(fixture.url)
                    } label: {
                        Label("Open File", systemImage: "doc.text")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([fixture.url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
            }
        }
    }

    private func footerBar() -> some View {
        HStack {
            footerButton(imageSystemName: "plus") {
                let newRule = Rule(endpoint: .init(path: "/some/endpoint/"), responsePolicy: .alwaysAsk)
                store.send(.exchange(.addOrUpdateRule(newRule)))
                selectedRuleIDs = [newRule.id]
                focusedRule = newRule.id
            }

            Divider()
                .frame(height: 20)

            footerButton(imageSystemName: "minus") {
                store.send(.exchange(.removeRules(selectedRuleIDs)))
            }
            Spacer()
        }
        .padding(.top, 4)
        .background(.regularMaterial)
        .buttonStyle(.borderless)
    }

    private func footerButton(
        imageSystemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: imageSystemName)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
    }

    // MARK: - Private Methods (Helpers)

    private func sortAndAutoScroll(scrollView: ScrollViewProxy) {
        // Don't sort while the user is focusing/editing
        if focusedRule == nil {
            store.send(.exchange(.sortRules(sortOrder)))
        }

        // Auto-scroll to the selected rule.
        // If the user is multi-selecting, don't do anything; just let the default Table scrolling behavior kick in
        if selectedRuleIDs.count == 1, let id = selectedRuleIDs.first {
            // Dispatch to scroll after layout completes
            DispatchQueue.main.async {
                withAnimation {
                    scrollView.scrollTo(id)
                }
            }
        }
    }

    /// Remove duplicate rules. Ideally this logic would live in the Reducer,
    /// but we don't want to interrupt the user while they're editing a rule.
    /// Editing state is managed by the view (via @FocusState), so we handle it here.
    private func removeDuplicateRules(_ rules: IdentifiedArrayOf<Rule>) {
        guard focusedRule == nil else { return }

        var seenRules: Set<Rule> = []
        var duplicatesToRemove: Set<Rule.ID> = []
        var duplicatesToKeep: Set<Rule.ID> = []

        for rule in rules.reversed() {
            if let existingRule = seenRules.first(where: { $0.endpoint == rule.endpoint}) {
                duplicatesToRemove.insert(rule.id)
                duplicatesToKeep.insert(existingRule.id)
            }
            seenRules.insert(rule)
        }

        // Remove the duplicates
        store.send(.exchange(.removeRules(duplicatesToRemove)))

        // To help the user understand that duplicates were removed,
        // auto-select the duplicate rules that we kept.
        if !duplicatesToKeep.isEmpty {
            selectedRuleIDs = duplicatesToKeep
        }
    }
    
    private func createNewFixtureForRule(rule: Rule, fixturesRepoPath: String, viewStore: ViewStore<AppState, AppAction>) {
        guard !fixturesRepoPath.isEmpty else {
            showAlert(
                title: "Fixtures Path Not Set",
                message: "Please set the fixtures repository path in the Settings > Fixtures section."
            )
            return
        }
        
        // Build the full directory path: fixtures + endpoint path
        let fixturesBaseURL = URL(fileURLWithPath: fixturesRepoPath)
        let endpointPath = rule.endpoint.path
        let fullDirectoryURL = fixturesBaseURL.appendingPathComponent(endpointPath, isDirectory: true)
        
        // Prompt for filename using an alert with text input
        let alert = NSAlert()
        alert.messageText = "Create New Fixture"
        alert.informativeText = "Enter a filename for the fixture:\n\nIt will be created at:\n\(fullDirectoryURL.path)"
        alert.alertStyle = .informational
        
        // Create text field for filename input
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "fixture.json"
        textField.placeholderString = "filename.json"
        alert.accessoryView = textField
        
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        // Set the text field as first responder so it's focused
        alert.window.initialFirstResponder = textField
        
        // Select all text in the field for easy editing
        DispatchQueue.main.async {
            textField.currentEditor()?.selectAll(nil)
        }
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            // User canceled
            return
        }
        
        var filename = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure filename is not empty
        guard !filename.isEmpty else {
            showAlert(
                title: "Invalid Filename",
                message: "Please provide a valid filename."
            )
            return
        }
        
        // Add .json extension if not present
        if !filename.hasSuffix(".json") {
            filename += ".json"
        }
        
        // Create the directory structure
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: fullDirectoryURL, withIntermediateDirectories: true)
        } catch {
            showAlert(
                title: "Failed to Create Directory",
                message: "Could not create directory at \(fullDirectoryURL.path)\n\nError: \(error.localizedDescription)"
            )
            return
        }
        
        // Create an empty fixture file
        let fixtureFileURL = fullDirectoryURL.appendingPathComponent(filename)
        let emptyJSON = "{\n  \n}\n"
        
        do {
            try emptyJSON.write(to: fixtureFileURL, atomically: true, encoding: .utf8)
        } catch {
            showAlert(
                title: "Failed to Create File",
                message: "Could not create fixture at \(fixtureFileURL.path)\n\nError: \(error.localizedDescription)"
            )
            return
        }
        
        // Open the file in the default editor
        NSWorkspace.shared.open(fixtureFileURL)
        
        // Reload fixtures to show the newly created file in the list
        viewStore.send(.load(.loadResponseFixtures))
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - ViewStore Conveniences

extension ViewStore where ViewState == AppState, ViewAction == AppAction {

    func endpointPathBinding(for rule: Rule) -> Binding<String> {
        binding(
            get: { state in state.rules[id: rule.id]?.endpoint.path ?? "" },
            send: { newPath in
                var updatedRule = rule
                updatedRule.endpoint = .init(path: newPath)
                return .exchange(.addOrUpdateRule(updatedRule))
            }
        )
    }

    func responsePolicyBinding(for rule: Rule) -> Binding<ResponsePolicy> {
        binding(
            get: { state in
                state.rules[id: rule.id]?.responsePolicy ?? .alwaysAsk
            },
            send: { newResponsePolicy in
                var updatedRule = rule
                updatedRule.responsePolicy = newResponsePolicy
                return .exchange(.addOrUpdateRule(updatedRule))
            }
        )
    }

    func textSuggestions(for rule: Rule) -> [String] {
        Set(state.exchanges.map(\.request.endpoint.path))
            .filter { path in
                path == rule.endpoint.path ? false : path.localizedCaseInsensitiveContains(rule.endpoint.path)
            }
            .sorted()
    }
}

// MARK: -

extension View {

    /// Enable text input suggestions on supported OS versions
    @ViewBuilder
    func withTextInputSuggestions(_ suggestions: [String]) -> some View {
        if #available(macOS 15.0, *) {
            self.textInputSuggestions {
                ForEach(suggestions, id: \.self) { suggestion in
                    Label(suggestion, systemImage: "clock")
                        .textInputCompletion(suggestion)
                }
            }
        } else {
            self
        }
    }
}
