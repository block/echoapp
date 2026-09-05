import SwiftUI

struct PluginImportResultsView: View {
    // MARK: - Properties
    
    let importedPlugins: [PluginExportTable.PluginData]
    
    // MARK: - View
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Successful")
                .font(.headline)

            VStack {
                Table(importedPlugins.sorted { $0.messageCount > $1.messageCount }) {
                    TableColumn("Plugin") { plugin in
                        Text(plugin.plugin.plugin.metadata.displayName)
                    }

                    TableColumn("Messages") { plugin in
                        Text("\(plugin.messageCount)")
                    }
                    .width(80)
                }
                .cornerRadius(8)
            }
            
            HStack {
                Spacer()
                Text("\(importedPlugins.reduce(0) { $0 + $1.messageCount }) messages imported to \(importedPlugins.count) plugins")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
