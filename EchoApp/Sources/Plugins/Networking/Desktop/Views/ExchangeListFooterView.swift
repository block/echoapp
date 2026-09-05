import ComposableArchitecture
import EchoPluginUI
import SwiftUI

struct ExchangeListFooterView: View {
    let store: Store<AppState, AppAction>
    
    @State private var isShowingSettings: Bool = false

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            EchoListFooterView(
                itemCount: viewStore.filteredExchanges.count,
                itemLabel: "request",
                itemLabelPlural: "requests",
                actionButtons: [
                    .init(
                        iconName: "trash",
                        helpText: "Clear    ⌘K",
                        isDestructive: true,
                        action: { viewStore.send(.exchange(.clearExchanges)) }
                    )
                ]
            ) {
                Button {
                    isShowingSettings.toggle()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(FooterButtonStyle())
                .popover(
                    isPresented: $isShowingSettings,
                    arrowEdge: .top,
                    content: { ExchangeSettingsView(store: store) }
                )
            }
        }
    }
}
