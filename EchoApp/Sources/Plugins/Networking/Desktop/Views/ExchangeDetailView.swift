import Combine
import ComposableArchitecture
import EchoPluginUI
import SwiftUI

/// Responsible for displaying information about an exchange, including the request and response bodies.
struct ExchangeDetailView: View {
    let store: Store<AppState, AppAction>
    let exchange: Exchange

    // MARK: - View

    var body: some View {
        WithViewStore(store, observe: \.exchangeDetailPaneConfiguration) { viewStore in
            HSplitView {
                if viewStore.shouldShowRequest {
                    requestPane()
                    .frame(minWidth: 300)
                }
                if viewStore.shouldShowResponse {
                    responsePane()
                    .frame(minWidth: 300)
                }
            }
            .frame(minWidth: 600)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    paneConfigurationMenu(currentConfiguration: viewStore.state)
                }
            }
            .onHotKeyEvent(key: "=", modifierFlags: .command) {
                viewStore.send(.ui(.updateDetailViewFontSize(.increment)))
            }
            .onHotKeyEvent(key: "-", modifierFlags: .command) {
                viewStore.send(.ui(.updateDetailViewFontSize(.decrement)))
            }
        }
    }

    // MARK: -

    private func requestPane() -> some View {
        WithViewStore(store, observe: \.self) { viewStore in
            ExchangeDetailPane(
                store: store,
                type: .request,
                subtitle: exchange.request.url.path(),
                footerLabel: exchange.request.httpMethod,
                responseSuccess: nil,
                exchange: exchange,
                tabSelection: viewStore.binding(
                    get: \.selectedRequestTab,
                    send: { tab in
                        .exchange(.exchangeTabTappedAt(.request, tab))
                    }
                ),
                copyBlock: {
                    store.send(
                        .exchange(
                            .copyExchangeInformationToClipboard(.request, exchange)
                        )
                    )
                },
                updateRuleBlock: {
                    store.send(
                        .ui(.openSettingsForRule(exchange.rule))
                    )
                },
                saveFixtureBlock: nil,
                content: {
                    RequestDetailView(
                        store: store,
                        request: exchange.request
                    )
                },
                defaultResponsePolicy: viewStore.defaultResponsePolicy,
                assumeProxyingEnabled: viewStore.assumeProxyingEnabled
            )
        }
    }

    private func responsePane() -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            let footerLabel: String? = exchange.state.finalizedPolicyDescription ?? exchange.state.description
            ExchangeDetailPane(
                store: store,
                type: .response,
                subtitle: self.exchange.state.description,
                footerLabel: footerLabel,
                responseSuccess: self.exchange.response?.isSuccessful,
                exchange: exchange,
                tabSelection: viewStore.binding(
                    get: \.selectedResponseTab,
                    send: { tab in
                        .exchange(.exchangeTabTappedAt(.response, tab))
                    }
                ),
                copyBlock: {
                    store.send(
                        .exchange(.copyExchangeInformationToClipboard(.response, exchange))
                    )
                },
                updateRuleBlock: nil,
                saveFixtureBlock: exchange.response.map { response in
                    { store.send(.ui(.saveFixture(exchange.request.endpoint, response))) }
                },
                content: {
                    ResponseDetailView(
                        store: store,
                        exchange: exchange
                    )
                },
                defaultResponsePolicy: viewStore.defaultResponsePolicy,
                assumeProxyingEnabled: viewStore.assumeProxyingEnabled
            )
        }
    }

    private func paneConfigurationMenu(currentConfiguration: ExchangeDetailPaneConfiguration) -> some View {
        Menu {
            ForEach(ExchangeDetailPaneConfiguration.allCases) { configOption in
                Button {
                    store.send(.ui(.setExchangeDetailPaneConfiguration(configOption)))
                } label: {
                    let isChecked = currentConfiguration == configOption
                    Text("\(isChecked ? "✓" : "\u{2007} ") \(configOption.rawValue)")
                }
            }
        } label: {
            switch currentConfiguration {
            case .request:
                Image(systemName: "rectangle.leadinghalf.filled")
            case .response:
                Image(systemName: "rectangle.trailinghalf.filled")
            case .both:
                Image(systemName: "rectangle.split.2x1.fill")
            }
        }
    }
}

// MARK: -

private struct ExchangeDetailPane<Content>: View where Content: View {
    enum ExchangeDetailPaneType {
        case request
        case response

        var label: String {
            switch self {
            case .request:
                "Request"
            case .response:
                "Response"
            }
        }
    }

    let store: Store<AppState, AppAction>
    let type: ExchangeDetailPaneType
    let subtitle: String?
    let footerLabel: String?
    let responseSuccess: Bool?
    let exchange: Exchange
    let tabSelection: Binding<ExchangeDetailTab>
    let copyBlock: () -> Void
    let updateRuleBlock: (() -> Void)?
    let saveFixtureBlock: (() -> Void)?
    let content: () -> Content
    let defaultResponsePolicy: ResponsePolicy
    let assumeProxyingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(type.label)
                        .font(Font.Fakelin.sectionHeader)
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                EchoToolbarNavigationPicker(
                    segments: availableTabs,
                    selection: tabSelection
                )
                .frame(minWidth: 100)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            content()
                .background(Color.Fakelin.windowPaneBackground)
                .frame(
                    minWidth: 300,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            makeFooter()
        }
    }

    private var availableTabs: [(icon: String, label: String, value: ExchangeDetailTab)] {
        [
            (icon: "list.dash.header.rectangle", label: "Headers", value: ExchangeDetailTab.headers),
            (icon: "text.document.fill", label: "Body", value: ExchangeDetailTab.body),
            (icon: "curlybraces.square", label: "Raw", value: ExchangeDetailTab.raw),
        ]
    }

    private func policyStatusLabel(_ policy: ResponsePolicy, type: ExchangeDetailPaneType) -> String {
        switch policy {
        case .alwaysAsk: return "Always Ask"
        case .proxy: return "Proxy Original"
        case .fixture(let fixture):
            switch type {
            case .request:
                return "Fixture"
            case .response:
                return "Fixture – \(fixture.url.lastPathComponent)"
            }
        case .custom(let custom):
            switch type {
            case .request:
                return custom.name
            case .response:
                return "Custom – \(custom.name)"
            }
        }
    }

    private func makeFooter() -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 8) {
                if assumeProxyingEnabled {
                    makePolicySection(store: store)
                }
                Spacer()
                if let saveFixtureBlock, tabSelection.wrappedValue == .body {
                    Button {
                        saveFixtureBlock()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down.square.fill")
                            Text("Save Fixture")
                        }
                    }
                    .buttonStyle(FooterButtonStyle())
                }
                FixtureCopyButton { _ in
                    copyBlock()
                    return true
                }
                .buttonStyle(FooterButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func makePolicySection(store: Store<AppState, AppAction>) -> some View {
        switch type {
        case .request:
            makeRequestPolicySection(store: store)
        case .response:
            makeResponsePolicySection(store: store)
        }
    }
    
    @ViewBuilder
    private func makeRequestPolicySection(store: Store<AppState, AppAction>) -> some View {
        // Show what policy will be used for future requests to this endpoint
        if let rule = exchange.rule {
            // There's a specific rule for this endpoint
            HStack(spacing: 4) {
                Image(systemName: rule.responsePolicy.symbol)
                Text("\(policyStatusLabel(rule.responsePolicy, type: .request))")
            }
            .foregroundStyle(.secondary)
            .help("Custom Rule")
            Button("Edit Rule") {
                updateRuleBlock?()
            }
            .buttonStyle(FooterButtonStyle())
        } else {
            // No specific rule, will use default
            HStack(spacing: 4) {
                Image(systemName: defaultResponsePolicy.symbol)
                Text("\(policyStatusLabel(defaultResponsePolicy, type: .request))")
            }
            .foregroundStyle(.secondary)
            .help("Default Rule")
            Button("New Rule") {
                store.send(.ui(.createRuleForEndpoint(exchange.request.endpoint)))
            }
            .buttonStyle(FooterButtonStyle())
        }
    }
    
    @ViewBuilder
    private func makeResponsePolicySection(store: Store<AppState, AppAction>) -> some View {
        // Show what policy was actually used for this specific response
        if case let .finalizedResponse(_, selectedPolicy) = exchange.state {
            HStack(spacing: 4) {
                Image(systemName: selectedPolicy.symbol)
                Text("\(policyStatusLabel(selectedPolicy, type: .response))")
                    .help("Applied Rule")
            }
            .foregroundStyle(.secondary)
        }
    }
}

public struct FixtureCopyButton: View {
    public let copyBlock: (NSPasteboard) -> Bool
    @State private var copyText = Strings.defaultCopyText

    public init(copyBlock: @escaping (NSPasteboard) -> Bool) {
        self.copyBlock = copyBlock
    }

    public var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            // Update the button text based on the success of the copy operation.
            copyText = copyBlock(pasteboard) ? Strings.copiedText : Strings.failedText
            // Reset the button text after a delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copyText = Strings.defaultCopyText
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "document.on.clipboard.fill")
                    .font(.caption)
                Text(copyText)
            }
        }
        .buttonStyle(FooterButtonStyle())
    }

    private enum Strings {
        static let defaultCopyText = "Copy"
        static let copiedText = "Copied!"
        static let failedText = "Failed!"
    }

}
