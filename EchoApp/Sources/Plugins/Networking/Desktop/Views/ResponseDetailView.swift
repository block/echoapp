import ComposableArchitecture
import SwiftUI
import EchoPluginAPI

struct ResponseDetailView: View {
    let store: Store<AppState, AppAction>
    let exchange: Exchange

    // MARK: - View

    var body: some View {
        WithViewStore(store, observe: { $0 }) { _ in
            switch exchange.state {
            case let .pendingResponse(_, errorMessage):
                if let errorMessage {
                    // Show only the error message when there's an error
                    GroupBox {
                        Text(errorMessage)
                            .italic()
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .padding()
                } else {
                    // Show response policy picker when there's no error
                    makeResponsePolicyPickerView()
                }

            case .waitingForClientProvidedResponse, .sendingResponse:
                ActivityIndicator(controlSize: .regular)

            case let .finalizedResponse(response, _):
                makeFinalizedResponseView(response: response)
            }
        }
    }

    // MARK: - Private Methods

    private var isExchangePendingResponse: Bool {
        if case .pendingResponse = exchange.state { return true }
        return false
    }

    /// The view shown when the client has provided the finalized response
    private func makeFinalizedResponseView(response: HumanReadableResponse) -> some View {

        func makeResponseContentView() -> some View {
            WithViewStore(store, observe: { $0 }) { viewStore in
                switch viewStore.selectedResponseTab {
                case .headers:
                    ScrollableText(
                        response.headers.prettyPrintedJSON,
                        shouldHighlight: viewStore.enableJsonHighlighting, fontSize: viewStore.detailViewFontSize
                    ).onAppear {
                        viewStore.send(
                            AppAction.exchange(
                                .exchangeTabTappedAt(.response, .headers)
                            )
                        )
                    }
                case .body:
                    ScrollableText(
                        response.body,
                        shouldHighlight: viewStore.enableJsonHighlighting, fontSize: viewStore.detailViewFontSize
                    ).onAppear {
                        viewStore.send(
                            AppAction.exchange(
                                .exchangeTabTappedAt(.response, .body)
                            )
                        )
                    }
                case .raw:
                    ScrollableText(
                        response.body,
                        shouldHighlight: false,
                        fontSize: viewStore.detailViewFontSize
                    ).onAppear {
                        viewStore.send(
                            AppAction.exchange(
                                .exchangeTabTappedAt(.response, .raw)
                            )
                        )
                    }
                }
            }
        }

        return makeResponseContentView()
    }

    /// The view shown which allows the user to choose a response policy to handle the current request.
    private func makeResponsePolicyPickerView() -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ResponsePolicyPickerView(
                store: self.store,
                endpoint: self.exchange.request.endpoint,
                defaultResponsePolicies: viewStore.state.liveResponsePolicies(for: exchange.request.endpoint),
                selectedResponsePolicy: nil,
                onSelect: { selectedPolicy in
                    viewStore.send(.exchange(.chooseResponsePolicy(self.exchange, selectedPolicy)))
                }
            )
        }
    }

}
