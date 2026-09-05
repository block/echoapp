import ComposableArchitecture
import EchoPluginUI
import SwiftUI

/// Displays the main interface for the app: a list of exchanges and a detail view showing information about the selected exchange
public struct MainView: View {

    // MARK: - Private Types
    private enum Metrics {
        static let minWindowSize = NSSize(width: 500, height: 500)
    }

    // MARK: - Private Properties

    private let store: Store<AppState, AppAction>

    // MARK: - Life Cycle

    public init(store: Store<AppState, AppAction>) {
        self.store = store
    }

    // MARK: - View

    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                if viewStore.isShowingRuleSettings {
                    RoutingRulesView(store: store, focusedRuleID: viewStore.focusedRuleID)
                } else {
                    mainBody
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("View", selection: viewStore.binding(
                        get: \.isShowingRuleSettings,
                        send: { .ui(.navigate(.showRules($0))) }
                    )) {
                        Label("Calls", systemImage: "list.dash").tag(false)
                        Label("Rules", systemImage: "gear").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var mainBody: some View {
        HSplitView {
            makeListView()
                .frame(
                    minWidth: Constants.listMinimumWidth,
                    maxWidth: Constants.listMaximumWidth
                )
            makeDetailView()
                .frame(
                    minWidth: Constants.detailMinimumWidth,
                    maxWidth: Constants.detailMaximumWidth,
                    maxHeight: Constants.detailMaximumHeight
                )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    func makeListView() -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ExchangeListView(store: self.store)
                .searchable(
                    text: viewStore.binding(
                        get: \.filters.searchText,
                        send: { .ui(.setSearchText($0)) }
                    ),
                    prompt: "Search path, headers, body, or status"
                )
        }
    }

    func makeDetailView() -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            if let exchange = viewStore.selectedExchange {
                ExchangeDetailView(store: self.store, exchange: exchange)
            } else {
                EchoNullStateView(
                    iconName: "filemenu.and.cursorarrow",
                    message: "Inspect a network call\nby selecting one from the list."
                )
            }
        }
    } 
}

// MARK: -

private enum Constants {

    static let searchFieldPadding: CGFloat = 8

    static let listMinimumWidth: CGFloat = 250
    static let listMaximumWidth: CGFloat = 400

    static let detailMinimumWidth: CGFloat = 600
    static let detailMaximumWidth: CGFloat = .infinity
    static let detailMaximumHeight: CGFloat = .infinity

}
