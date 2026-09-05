import SwiftUI

struct PluginExportTable: View {
    // MARK: - Types
    
    struct PluginData: Identifiable, Equatable {
        let id: String
        let plugin: LoadedPlugin
        let messageCount: Int
        var isSelected: Bool
        
        static func == (lhs: PluginData, rhs: PluginData) -> Bool {
            lhs.id == rhs.id &&
            lhs.plugin == rhs.plugin &&
            lhs.messageCount == rhs.messageCount &&
            lhs.isSelected == rhs.isSelected
        }
    }
    
    // MARK: - Properties
    
    @State var pluginData: [PluginData]
    let onSelectionChanged: (Int, Int) -> Void  // (messages, plugins)
    
    // MARK: - View
    
    var body: some View {
        VStack {
            Table(pluginData) {
                TableColumn("") { plugin in
                    Toggle("", isOn: binding(for: plugin))
                        .disabled(plugin.messageCount == 0)
                }
                .width(20)

                TableColumn("Plugin") { plugin in
                    Text(plugin.plugin.plugin.metadata.displayName)
                }

                TableColumn("Messages") { plugin in
                    Text("\(plugin.messageCount)")
                }
                .width(80)
            }
        }
    }
    
    // MARK: - Bindings
    
    private func binding(for plugin: PluginData) -> Binding<Bool> {
        Binding(
            get: {
                if let index = pluginData.firstIndex(where: { $0.id == plugin.id }) {
                    return pluginData[index].isSelected
                }
                return false
            },
            set: { newValue in
                if let index = pluginData.firstIndex(where: { $0.id == plugin.id }) {
                    pluginData[index].isSelected = newValue
                    
                    // Calculate total selected messages and plugins
                    let selectedPlugins = pluginData.filter { $0.isSelected && $0.messageCount > 0 }
                    let totalMessages = selectedPlugins.reduce(0) { $0 + $1.messageCount }
                    let totalPlugins = selectedPlugins.count
                    
                    onSelectionChanged(totalMessages, totalPlugins)
                }
            }
        )
    }
}
