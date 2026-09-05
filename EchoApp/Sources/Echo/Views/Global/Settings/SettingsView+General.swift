import SwiftUI

struct GeneralSettingsView: View {
    let appViewModel: AppViewModel

    @AppStorage("shouldAutoReconnectToClient") private var shouldAutoReconnect = true
    @AppStorage("MainSidebar.showMessageCount") private var showMessageCount = true
    @AppStorage("MainSidebar.dimInactivePlugins") private var dimInactivePlugins = false
    @AppStorage("MainSidebar.hideInactivePlugins") private var hideInactivePlugins = false
    @AppStorage("MainSidebar.sectionGroupingKey") private var groupKey: MetadataGroupKey = .targetAppDisplayName

    var body: some View {
        HStack {
            Spacer()
            Form {
                Section(header: Text("Clients")) {
                    Toggle("Automatically reconnect to last connected client", isOn: $shouldAutoReconnect)
                    firewallExceptionsRow
                }

                Section(header: Text("Sidebar")) {
                    Toggle("Dim inactive plugins", isOn: $dimInactivePlugins)
                    Toggle("Hide inactive plugins", isOn: $hideInactivePlugins)
                    Toggle("Show message count", isOn: $showMessageCount)
                }

                Section(header: Text("Sections")) {
                    Picker("Group by", selection: $groupKey) {
                        ForEach(MetadataGroupKey.allCases, id: \.rawValue) { key in
                            Text(key.rawValue).tag(key)
                        }
                    }
                }
            }
            .frame(maxWidth: 500)
            .formStyle(.grouped)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var firewallExceptionsRow: some View {
        HStack {
            Text("iOS Development Firewall Exceptions")
                .help(
                    """
                    Enable Firewall exceptions to prevent macOS from displaying the \
                    'Do you want the application to accept incoming network connections?' \
                    prompt every time the iOS Simulator launches.
                    """
                )

            switch appViewModel.firewallState {
            case .unknown:
                Text("Unknown")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {
                    appViewModel.updateFirewallState()
                }

            case let .known(exceptionsEnabled):
                Text(exceptionsEnabled ? "Enabled" : "Disabled")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(exceptionsEnabled ? "Disable" : "Enable") {
                    appViewModel.toggleFirewallExceptions()
                }
            }
        }
    }
}
