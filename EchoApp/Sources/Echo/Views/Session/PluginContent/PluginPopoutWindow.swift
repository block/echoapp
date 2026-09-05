import EchoPluginAPI
import SwiftUI

/// The view shown when a plugin is opened in a separate window
struct PluginPopoutWindow: View {
    let appViewModel: AppViewModel
    @Binding var pluginID: PluginIdentifier?

    var body: some View {
        if let sessionViewModel = appViewModel.activeSession {
            VStack(spacing: 0) {
                if let connectedClient = sessionViewModel.connectedClient {
                    HStack(spacing: 8) {
                        Image(systemName: "apps.iphone")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(connectedClient.deviceName ?? connectedClient.deviceIdentifier.value)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(connectedClient.appIdentifier)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)

                    Divider()
                }

                if let pluginID = pluginID,
                   let plugin = sessionViewModel.loadedPlugins[id: pluginID]?.plugin {
                    plugin.makeView()
                        .navigationTitle(plugin.metadata.displayName)
                } else {
                    EmptyView()
                }
            }
        } else {
            Text("No active session")
                .foregroundColor(.secondary)
        }
    }
}
