import AppKit
import ComposableArchitecture
import SwiftUI

struct ManageCustomResponsePoliciesView: View {
    let store: Store<AppState, AppAction>

    @State private var selectedResponsePolicies: Set<CustomResponsePolicy.ID> = []

    @State private var sortOrder: [KeyPathComparator<CustomResponsePolicy>] = [
        .init(\.name, order: .forward),
        .init(\.value.kind.description, order: .forward),
        .init(\.value.description, order: .forward),
    ]

    @FocusState private var focusedResponsePolicy: CustomResponsePolicy.ID?

    var body: some View {
        WithViewStore(store, observe: \.self) { viewStore in
            ScrollViewReader { scrollView in
                VStack(spacing: 0) {
                    table()
                    footerBar()
                }
                .onChange(of: sortOrder, initial: true) {
                    sortAndAutoScroll(scrollView: scrollView)
                }
                .onChange(of: viewStore.customResponsePolicies) {
                    sortAndAutoScroll(scrollView: scrollView)
                }
                .onChange(of: focusedResponsePolicy) {
                    sortAndAutoScroll(scrollView: scrollView)
                    removeDuplicateResponsePolicies(viewStore.customResponsePolicies)
                }
                .onChange(of: selectedResponsePolicies) {
                    sortAndAutoScroll(scrollView: scrollView)
                }
                .onDeleteCommand {
                    viewStore.send(.exchange(.removeCustomResponsePolicies(selectedResponsePolicies)))
                }
            }
        }
    }

    // MARK: - Private Methods (Subviews)

    private func table() -> some View {
        WithViewStore(store, observe: \.customResponsePolicies) { viewStore in
            Table(
                viewStore.state,
                selection: $selectedResponsePolicies,
                sortOrder: $sortOrder,
                columns: {
                    TableColumn("Name", value: \.name, content: nameColumnContent)
                    TableColumn("Type", value: \.value.kind.description, content: typeColumnContent)
                    TableColumn("Value", value: \.value.description, content: valueColumnContent)
                }
            )
            .tableStyle(.inset)
        }
    }

    private func nameColumnContent(_ responsePolicy: CustomResponsePolicy) -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            HStack(spacing: 4) {
                if isInvalidReroute(responsePolicy) {
                    Text("⚠️")
                        .help("Invalid reroute URL - must be a valid http:// or https:// URL")
                }
                textField(
                    binding: viewStore.nameBinding(for: responsePolicy),
                    responsePolicy: responsePolicy
                )
            }
        }
    }

    private func typeColumnContent(_ responsePolicy: CustomResponsePolicy) -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            Picker("Kind", selection: viewStore.kindBinding(for: responsePolicy)) {
                ForEach(CustomResponsePolicy.Kind.allCases, id: \.self) { kind in
                    Text(kind.description).tag(kind)
                        .help(kind.helpText)
                }
            }
            .labelsHidden()
            .buttonStyle(.borderless)
            .help(responsePolicy.value.kind.helpText)
        }
    }

    private func valueColumnContent(_ responsePolicy: CustomResponsePolicy) -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            let textBinding = switch responsePolicy.value {
            case .reroute:
                viewStore.rerouteBinding(for: responsePolicy)
            case .httpStatusCode:
                viewStore.httpStatusCodeBinding(for: responsePolicy)
            }
            textField(binding: textBinding, responsePolicy: responsePolicy)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(isInvalidReroute(responsePolicy) ? .red : .primary)
        }
    }

    private func textField(
        binding: Binding<String>,
        responsePolicy: CustomResponsePolicy
    ) -> some View {
        TextField("", text: binding)
            .focused($focusedResponsePolicy, equals: responsePolicy.id)
            .onSubmit {
                // Validate reroute URLs
                if case .reroute = responsePolicy.value {
                    validateRerouteURL(binding.wrappedValue)
                }
                focusedResponsePolicy = nil
            }
    }
    
    private func validateRerouteURL(_ urlString: String) {
        guard !urlString.isEmpty else { return }
        
        // Check if it's a valid HTTP/HTTPS URL
        guard let url = URL(string: urlString),
              (url.scheme == "http" || url.scheme == "https"),
              url.host != nil else {
            showInvalidRerouteAlert(urlString)
            return
        }
    }
    
    private func showInvalidRerouteAlert(_ invalidURL: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid Reroute URL"
        alert.informativeText = """
            "\(invalidURL)" is not a valid base URL for rerouting requests.
            
            ❌ Common mistakes:
            • Using a filename like "myfile.json"
            • Using a file path like "/path/to/file"
            • Missing the http:// or https:// prefix
            
            ✅ Expected format:
            • http://localhost:8080
            • https://api.staging.example.com
            
            The URL must include a scheme (http:// or https://) and a valid host.
            
            💡 Did you mean to use a Fixture instead?
            If you're trying to use a JSON file, select it from the Response dropdown in Rules, not from Custom Responses.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func isInvalidReroute(_ responsePolicy: CustomResponsePolicy) -> Bool {
        // Only validate reroute types
        guard case let .reroute(url) = responsePolicy.value else {
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

    private func footerBar() -> some View {
        HStack {
            footerButton(imageSystemName: "plus") {
                let newPolicy = CustomResponsePolicy(
                    name: "Custom Response",
                    value: .reroute()
                )
                store.send(.exchange(.addOrUpdateCustomResponsePolicy(newPolicy)))
                selectedResponsePolicies = [newPolicy.id]
                focusedResponsePolicy = newPolicy.id
            }

            Divider()
                .frame(height: 20)

            footerButton(imageSystemName: "minus") {
                store.send(.exchange(.removeCustomResponsePolicies(selectedResponsePolicies)))
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
        if focusedResponsePolicy == nil {
            store.send(.exchange(.sortCustomResponsePolicies(sortOrder)))
        }

        // Auto-scroll to the selected row.
        // If the user is multi-selecting, don't do anything; just let the default Table scrolling behavior kick in
        if selectedResponsePolicies.count == 1, let id = selectedResponsePolicies.first {
            // Dispatch to scroll after layout completes
            DispatchQueue.main.async {
                withAnimation {
                    scrollView.scrollTo(id)
                }
            }
        }
    }

    /// Remove duplicate policies. Ideally this logic would live in the Reducer,
    /// but we don't want to interrupt the user while they're editing.
    /// Editing state is managed by the view (via @FocusState), so we handle it here.
    private func removeDuplicateResponsePolicies(_ policies: IdentifiedArrayOf<CustomResponsePolicy>) {
        guard focusedResponsePolicy == nil else { return }

        var seenPolicies: Set<CustomResponsePolicy> = []
        var duplicatesToRemove: Set<CustomResponsePolicy.ID> = []
        var duplicatesToKeep: Set<CustomResponsePolicy.ID> = []

        for policy in policies.reversed() {
            if let existingPolicy = seenPolicies.first(where: { $0.value.description == policy.value.description}) {
                duplicatesToRemove.insert(policy.id)
                duplicatesToKeep.insert(existingPolicy.id)
            }
            seenPolicies.insert(policy)
        }

        // Remove the duplicates
        store.send(.exchange(.removeCustomResponsePolicies(duplicatesToRemove)))

        // To help the user understand that duplicates were removed,
        // auto-select the duplicate policies that we kept.
        if !duplicatesToKeep.isEmpty {
            selectedResponsePolicies = duplicatesToKeep
        }
    }
}

// MARK: - ViewStore Conveniences

extension ViewStore where ViewState == AppState, ViewAction == AppAction {

    func nameBinding(for responsePolicy: CustomResponsePolicy) -> Binding<String> {
        binding(
            get: { state in
                state.customResponsePolicies[id: responsePolicy.id]?.name ?? ""
            },
            send: { newName in
                var updatedPolicy = responsePolicy
                updatedPolicy.name = newName
                return .exchange(.addOrUpdateCustomResponsePolicy(updatedPolicy))
            }
        )
    }

    func kindBinding(for responsePolicy: CustomResponsePolicy) -> Binding<CustomResponsePolicy.Kind> {
        binding(
            get: { state in
                state.customResponsePolicies[id: responsePolicy.id]?.value.kind ?? .httpStatusCode
            },
            send: { newKind in
                let oldKind = responsePolicy.value.kind

                var updatedPolicy = responsePolicy
                switch (oldKind, newKind) {
                case (.reroute, .reroute), (.httpStatusCode, .httpStatusCode):
                    // No change
                    break

                case (_, .reroute):
                    updatedPolicy.value = .reroute()

                case (_, .httpStatusCode):
                    updatedPolicy.value = .httpStatusCode()
                }
                return .exchange(.addOrUpdateCustomResponsePolicy(updatedPolicy))
            }
        )
    }

    func rerouteBinding(for responsePolicy: CustomResponsePolicy) -> Binding<String> {
        binding(
            get: { state in
                guard
                    let policy = state.customResponsePolicies[id: responsePolicy.id],
                    case let .reroute(baseURL) = policy.value
                else {
                    return ""
                }
                return baseURL.absoluteString
            },
            send: { newPath in
                let newBaseURL = URL(string: newPath) ?? URL(string: "http://localhost")!
                var updatedPolicy = responsePolicy
                updatedPolicy.value = .reroute(newBaseURL: newBaseURL)
                return .exchange(.addOrUpdateCustomResponsePolicy(updatedPolicy))
            }
        )
    }

    func httpStatusCodeBinding(for responsePolicy: CustomResponsePolicy) -> Binding<String> {
        binding(
            get: { state in
                guard
                    let policy = state.customResponsePolicies[id: responsePolicy.id],
                    case let .httpStatusCode(statusCode) = policy.value
                else {
                    return "200"
                }
                return statusCode.map { String($0) } ?? ""
            },
            send: { newStatusCode in
                var updatedPolicy = responsePolicy
                updatedPolicy.value = .httpStatusCode(Int(newStatusCode))
                return .exchange(.addOrUpdateCustomResponsePolicy(updatedPolicy))
            }
        )
    }
}
