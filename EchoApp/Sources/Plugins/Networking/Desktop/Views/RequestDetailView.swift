import ComposableArchitecture
import SwiftUI
import EchoPluginAPI

struct RequestDetailView: View {
    let store: Store<AppState, AppAction>

    let request: Request

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 8) {
                switch viewStore.selectedRequestTab {
                case .headers:
                    ScrollableText(
                        request.headers.prettyPrintedJSON,
                        shouldHighlight: viewStore.enableJsonHighlighting,
                        fontSize: viewStore.detailViewFontSize
                    ).onAppear {
                        viewStore.send(
                            AppAction.exchange(
                                .exchangeTabTappedAt(.request, .headers)
                            )
                        )
                    }
                case .body:
                    ScrollableText(
                        request.humanReadableBody,
                        shouldHighlight: viewStore.enableJsonHighlighting,
                        fontSize: viewStore.detailViewFontSize
                    ).onAppear {
                        viewStore.send(
                            AppAction.exchange(
                                .exchangeTabTappedAt(.request, .body)
                            )
                        )
                    }
                case .raw:
                    ScrollableText(
                        request.networkingRawBodyDisplayString,
                        shouldHighlight: false,
                        fontSize: viewStore.detailViewFontSize
                    ).onAppear {
                        viewStore.send(
                            AppAction.exchange(
                                .exchangeTabTappedAt(.request, .raw)
                            )
                        )
                    }
                }
            }
        }
    }
}
