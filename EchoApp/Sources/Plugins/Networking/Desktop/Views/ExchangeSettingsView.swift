import ComposableArchitecture
import SwiftUI

public struct ExchangeSettingsView: View {

    // MARK: - Private Properties

    private let store: Store<AppState, AppAction>
    @State private var excludedPathPatternsText = ""

    public init(store: Store<AppState, AppAction>) {
        self.store = store
    }

    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading) {
                maxRequestsView()
                excludedPathPatternsView()
                Divider()
                showFullURLOptionView()
                showTimestampOptionView()
            }
            .padding(12)
            .frame(width: 280)
        }
    }

    // MARK: - Private Methods

    private func maxRequestsView() -> some View {
        WithViewStore(store, observe: \.maxExchangesToKeep) { viewStore in
            HStack {
                Text("Max Requests")
                Spacer()
                TextField(
                    "Count",
                    text: Binding(
                        get: { String(viewStore.state) },
                        set: { value in
                            if let intValue = Int(value) {
                                viewStore.send(.exchange(.maxExchangesToKeepChanged(intValue)))
                            }
                        }
                    )
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 60)
            }
        }
    }

    private func showFullURLOptionView() -> some View {
        WithViewStore(store, observe: \.showFullURLs) { viewStore in
            Toggle(
                "Show full URLs",
                isOn: Binding(
                    get: { viewStore.state },
                    set: { viewStore.send(.ui(.setShowFullURLs($0))) }
                )
            )
        }
    }

    private func excludedPathPatternsView() -> some View {
        WithViewStore(store, observe: \.filters.excludedEndpointPaths) { viewStore in
            VStack(alignment: .leading, spacing: 4) {
                Text("Excluded Paths")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "/_status, /1.0/features/get-flags",
                    text: Binding(
                        get: { excludedPathPatternsText },
                        set: { value in
                            excludedPathPatternsText = value
                            viewStore.send(.ui(.setExcludedEndpointPaths(value.endpointPathPatterns)))
                        }
                    )
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onAppear {
                    excludedPathPatternsText = viewStore.state.joined(separator: ", ")
                }
                .onChange(of: viewStore.state) { paths in
                    if excludedPathPatternsText.endpointPathPatterns != paths {
                        excludedPathPatternsText = paths.joined(separator: ", ")
                    }
                }
            }
        }
    }

    private func showTimestampOptionView() -> some View {
        WithViewStore(store, observe: \.showTimestamps) { viewStore in
            Toggle(
                "Show timestamps",
                isOn: Binding(
                    get: { viewStore.state },
                    set: { viewStore.send(.ui(.setShowTimestamps($0))) }
                )
            )
        }
    }
}

private extension String {

    var endpointPathPatterns: [String] {
        components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .normalizedEndpointPathPatterns()
    }
}
