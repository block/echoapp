import Combine
import ComposableArchitecture
import EchoPluginUI
import SwiftUI

struct ExchangeListView: View {
    // Used to flash the scroll indicators when the app becomes active,
    // in case more exchanges were added while the app was in the background
    @Environment(\.appearsActive) var isAppActive

    @State private var scrollPosition: Exchange.ID?
    @State private var isPinnedToTop = true

    let store: Store<AppState, AppAction>

    // MARK: - View

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 0) {
                EchoListView(
                    contentCount: viewStore.filteredExchanges.count,
                    selectedId: viewStore.selectedExchange?.id,
                    onNavigateUp: {
                        viewStore.send(.ui(.navigate(.selectPreviousExchange)))
                    },
                    onNavigateDown: {
                        viewStore.send(.ui(.navigate(.selectNextExchange)))
                    },
                    nullState: {
                        EchoNullStateView(
                            iconName: "network.slash",
                            message: "No network calls."
                        )
                    }
                ) {
                    VStack(spacing: 0) {
                        ForEach(
                            viewStore.filteredExchanges,
                            content: self.makeExchangeRowView
                        )
                    }
                    .padding(8)
                }
                .onDeleteCommand {
                    if let selectedExchange = viewStore.selectedExchange {
                        viewStore.send(.exchange(.clearSelected(selectedExchange)))
                    }
                }
                .onHotKeyEvent(key: "k", modifierFlags: .command) {
                    viewStore.send(.exchange(.clearExchanges))
                }
                .onHotKeyEvent(key: "d", modifierFlags: .command) {
                    if let selectedExchangeID = viewStore.selectedExchange?.id {
                        viewStore.send(.ui(.starExchange(selectedExchangeID)))
                    }
                }
                .onHotKeyEvent(key: "S", modifierFlags: [.shift, .command]) {
                    if let selectedExchange = viewStore.selectedExchange,
                       let response = selectedExchange.response {
                        viewStore.send(.ui(.saveFixture(selectedExchange.request.endpoint, response)))
                    }
                }
                .scrollIndicatorsFlash(trigger: viewStore.filteredExchanges.count)
                .scrollIndicatorsFlash(trigger: isAppActive)
                ExchangeListFooterView(store: store)
            }
        }
    }

    // MARK: - Private Methods

    private func makeExchangeRowView(exchange: Exchange) -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ExchangeRowView(
                exchange: exchange,
                isSelected: exchange == viewStore.selectedExchange,
                isStarred: viewStore.starredExchanges.contains(exchange.id),
                index: viewStore.filteredExchanges.firstIndex(of: exchange) ?? 0,
                showFullURL: viewStore.showFullURLs,
                showTimestamp: viewStore.showTimestamps
            )
            .id(exchange.id)
            .contentShape(
                Rectangle() // Make the whole row tappable (not just the label and image)
            )
            .onClick {
                viewStore.send(.ui(.navigate(.selectExchange(exchange))))
            }
            .help(makeHelpText(exchange: exchange))
            .contextMenu {
                Button("Copy full exchange") {
                    viewStore.send(.ui(.copyCompleteExchangeInfo(exchange)))
                }

                Divider()
                
                Button("Filter by endpoint") {
                    viewStore.send(.ui(.setSearchText(exchange.request.endpoint.path)))
                }

                Button("Exclude endpoint") {
                    viewStore.send(.ui(.excludeEndpointPath(exchange.request.endpoint.path)))
                }

                Button("Copy path") {
                    viewStore.send(.ui(.copyRequestPath(exchange.request)))
                }

                Button("Copy full URL") {
                    viewStore.send(.ui(.copyRequestFullURL(exchange.request)))
                }

                Button("Copy as cURL") {
                    viewStore.send(.ui(.copyRequestAscURL(exchange.request)))
                }

                Divider()

                Button("Toggle star") {
                    viewStore.send(.ui(.starExchange(exchange.id)))
                }
                .keyboardShortcut("d")

                Button("Delete") {
                    viewStore.send(.exchange(.clearSelected(exchange)))
                }
                .keyboardShortcut(.delete)
            }
        }
    }

    private func makeHelpText(exchange: Exchange) -> Text {
        Text(exchange.request.url.absoluteString)
        + Text(" ")
        + Text(exchange.request.timestamp, style: .time)
    }

    private func pinToTopButton() -> some View {
        Button(
            "Pin to top",
            systemImage: "arrow.up.to.line.circle"
        ) {
            isPinnedToTop.toggle()
        }
        .labelsHidden()
        .buttonStyle(ToggleButtonStyle(isSelected: isPinnedToTop))
        .help("Pin to top")
    }

}

// MARK: -

private struct ExchangeRowView: View {
    @Environment(\.colorScheme) var colorScheme

    let exchange: Exchange
    let isSelected: Bool
    let isStarred: Bool
    let index: Int
    let showFullURL: Bool
    let showTimestamp: Bool

    var foregroundColor: Color {
        isSelected ? Color.Fakelin.selectedText : Color.Fakelin.text
    }
    var subtitleForegroundColor: Color {
        isSelected ? Color.Fakelin.selectedText : Color.secondary
    }
    var backgroundColor: Color {
        isSelected ? Color.Fakelin.selectedBackground : (index % 2 == 0 ? Color.clear : Color.gray.opacity(0.1))
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                requestEndpointSuffixView()

                if showFullURL {
                    fullRequestURLView()
                } else {
                    requestEndpointPrefixView()
                }
            }
            Spacer()
            isStarred
                ? Text("★").foregroundColor(foregroundColor)
                : nil
            if showTimestamp {
                timestampView()
            }
            makeAccessoryView()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .cornerRadius(4)
    }

    // MARK: - Private Methods

    /// Displays the last path component of the endpoint
    @ViewBuilder
    private func requestEndpointSuffixView() -> some View {
        Text(exchange.request.url.lastPathComponent)
            .foregroundStyle(foregroundColor)
            .font(.system(size: 11, design: .monospaced))
    }

    /// Displays all but the last path component of the endpoint
    @ViewBuilder
    private func requestEndpointPrefixView() -> some View {
        Text(exchange.request.url.deletingLastPathComponent().relativePath)
            .foregroundStyle(subtitleForegroundColor)
            .font(.footnote)
    }

    @ViewBuilder
    /// Displays the full URL of the request
    private func fullRequestURLView() -> some View {
        Text(exchange.request.url.absoluteString)
            .foregroundStyle(subtitleForegroundColor)
            .font(.footnote)
    }

    @ViewBuilder
    /// Displays the timestamp in the user's current timezone
    private func timestampView() -> some View {
        Text(exchange.request.timestamp.formatted(
            .dateTime.hour().minute().second().secondFraction(.fractional(3))
        ))
            .foregroundStyle(subtitleForegroundColor)
            .font(.footnote)
    }

    private func makeAccessoryView() -> some View {
        switch exchange.state {
        case .waitingForClientProvidedResponse, .pendingResponse, .sendingResponse:
            return AnyView(
                ActivityIndicator(controlSize: .small, appearance: activityIndicatorAppearance)
            )

        case let .finalizedResponse(response, _):
            let imageName = response.isSuccessful
                ? NSImage.statusAvailableName
                : NSImage.statusUnavailableName
            return AnyView(
                Image(nsImage: NSImage(named: imageName)!)
            )
        }
    }

    private var activityIndicatorAppearance: NSAppearance? {
        let appearanceName: NSAppearance.Name
        switch (colorScheme, isSelected) {
        case (.dark, _):
            appearanceName = .darkAqua

        case (.light, true):
            appearanceName = .darkAqua

        case (.light, false):
            appearanceName = .aqua

        default:
            appearanceName = .aqua
        }
        return NSAppearance(named: appearanceName)
    }

}

// MARK: -

fileprivate extension View {

    func onClick(_ action: @escaping () -> Void) -> some View {
        onLongPressGesture(minimumDuration: 0, perform: action)
    }
}

// MARK: -

extension View {

    /// Add an `onScrollPhaseChange` modifier that detects the user scrolling down (for supported OS versions)
    @ViewBuilder
    func onScrollDown(
        _ action: @escaping () -> Void
    ) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollPhaseChange { _, newPhase, context in
                if newPhase.isScrolling && context.velocity?.dy ?? 0 > 0 {
                    action()
                }
            }
        } else {
            self
        }
    }
}
