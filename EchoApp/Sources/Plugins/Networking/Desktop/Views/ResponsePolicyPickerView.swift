import AppKit
import Combine
import ComposableArchitecture
import SwiftUI
import EchoPluginAPI

/// Displays response policies that can be selected by the user, including fixtures.
struct ResponsePolicyPickerView: View {
    let store: Store<AppState, AppAction>

    /// The endpoint used to determine which fixtures to show. If endoint is `nil`, no fixtures will be shown.
    let endpoint: Endpoint?

    /// List of response policies that are available for all endpoints.
    /// Fixtures will be shown in a separate section alongside these defaults.
    let defaultResponsePolicies: [ResponsePolicy]

    /// The currently selected policy, or nil if no policy has been selected.
    let selectedResponsePolicy: ResponsePolicy?

    /// Called when the selected policy changes.
    let onSelect: (ResponsePolicy) -> Void

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack {
                    self.makeResponsePolicySection(policies: self.defaultResponsePolicies)

                    if let fixturePolicies = endpoint.flatMap(viewStore.state.fixtureResponsePolicies) {
                        makeResponsePolicySection(title: "Fixtures", policies: fixturePolicies)
                    }
                    
                    if let endpoint = endpoint {
                        makeCreateFixtureButton(endpoint: endpoint, fixturesRepoPath: viewStore.fixturesRepoPath)
                    }
                }
            }
            .frame(minWidth: 200)
            .onAppear {
                viewStore.send(.load(.loadResponseFixtures))
            }
        }
    }

    // MARK: - Private Methods

    private func makeResponsePolicySection(title: String? = nil, policies: [ResponsePolicy]) -> some View {
        let label = title.map(Text.init)
            .frame(alignment: .leading)
            .font(.subheadline)

        return GroupBox(label: label) {
            VStack {
                makeResponsePolicyRows(for: policies)
            }
        }
        .padding()
    }

    private func makeResponsePolicyRows(for responsePolicies: [ResponsePolicy]) -> some View {
        let sortedResponsePolicies = responsePolicies.sorted {
            $0.name.lowercased() < $1.name.lowercased()
        }
        return ForEach(sortedResponsePolicies, id: \.name, content: makeResponsePolicyRow)
    }

    private func makeResponsePolicyRow(responsePolicy: ResponsePolicy) -> some View {
        let isInvalid = isInvalidReroute(responsePolicy)
        
        return Button(action: { self.onSelect(responsePolicy) }) {
            ResponsePolicyRow(policy: responsePolicy, isInvalid: isInvalid)
        }
        .buttonStyle(
            SelectableRowButtonStyle(isSelected: responsePolicy == self.selectedResponsePolicy)
        )
        .disabled(isInvalid)
        .opacity(isInvalid ? 0.5 : 1.0)
    }
    
    private func makeCreateFixtureButton(endpoint: Endpoint, fixturesRepoPath: String) -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            GroupBox {
                Button {
                    createNewFixture(endpoint: endpoint, fixturesRepoPath: fixturesRepoPath, store: viewStore)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Fixture")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .buttonStyle(.borderedProminent)
                .help("Create a new fixture file for this endpoint with the correct directory structure")
            }
            .padding()
        }
    }
    
    private func createNewFixture(endpoint: Endpoint, fixturesRepoPath: String, store: ViewStore<AppState, AppAction>) {
        guard !fixturesRepoPath.isEmpty else {
            showAlert(
                title: "Fixtures Path Not Set",
                message: "Please set the fixtures repository path in the Settings > Fixtures section."
            )
            return
        }
        
        // Build the full directory path: fixtures + endpoint path
        let fixturesBaseURL = URL(fileURLWithPath: fixturesRepoPath)
        let endpointPath = endpoint.path
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
        store.send(.load(.loadResponseFixtures))
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func isInvalidReroute(_ responsePolicy: ResponsePolicy) -> Bool {
        // Only validate custom response policies with reroute values
        guard case let .custom(customPolicy) = responsePolicy,
              case let .reroute(url) = customPolicy.value else {
            return false
        }
        
        let urlString = url.absoluteString
        
        // Check if it's empty or not a valid HTTP/HTTPS URL
        if urlString.isEmpty {
            return false // Empty is ok, just not filled in yet
        }
        
        // Check if it has the right scheme and host
        guard (url.scheme == "http" || url.scheme == "https"),
              url.host != nil else {
            return true
        }
        
        return false
    }

}

// MARK: -

private struct ResponsePolicyRow: View {
    let policy: ResponsePolicy
    let isInvalid: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isInvalid {
                Text("⚠️")
                    .help("Invalid reroute URL. Expected format: http://localhost:8080 or https://api.example.com")
            }
            Text(policy.name)
                .foregroundColor(isInvalid ? .red : nil)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: -

private struct SelectableRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Self.Configuration) -> some View {
        let highlighted = isSelected || configuration.isPressed
        let foregroundColor = highlighted ? Color.Fakelin.selectedText : Color.Fakelin.text
        let backgroundColor = highlighted ? Color.Fakelin.selectedBackground : Color.Fakelin.background

        return configuration.label
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .contentShape(Rectangle()) // Make the whole row tappable
    }

}
