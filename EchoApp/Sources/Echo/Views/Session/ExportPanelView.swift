import SwiftUI
import UniformTypeIdentifiers

struct ExportPanelView: View {
    let sessionViewModel: SessionViewModel

    @State private var selectedMessages = 0
    @State private var selectedPlugins = 0

    var body: some View {
        VStack(spacing: 16) {
            headerSection
            pluginTableSection
            summarySection
            if let error = sessionViewModel.exportState.error {
                errorSection(error: error)
            }
            exportButtonSection
        }
        .padding(20)
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 800, minHeight: 400, idealHeight: 500, maxHeight: 800)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            updateCounts(from: sessionViewModel.exportState.pluginData)
        }
        .onChange(of: sessionViewModel.exportState.pluginData) { _, newValue in
            updateCounts(from: newValue)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Text("Save Plugin Data")
                .font(.headline)
            Spacer()
            Button("Cancel") {
                sessionViewModel.dismissExport()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var pluginTableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select plugins to save:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Table(sessionViewModel.exportState.pluginData) {
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
            .frame(minHeight: 200, maxHeight: .infinity)
            .border(Color.secondary.opacity(0.2))
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        HStack {
            Text("\(selectedPlugins) plugin\(selectedPlugins == 1 ? "" : "s"), \(selectedMessages) message\(selectedMessages == 1 ? "" : "s") selected")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func errorSection(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.orange)
            Spacer()
        }
    }

    @ViewBuilder
    private var exportButtonSection: some View {
        HStack {
            Spacer()
            Button("Save...") {
                showSavePanel()
            }
            .disabled(selectedPlugins == 0)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func binding(for plugin: PluginExportTable.PluginData) -> Binding<Bool> {
        Binding(
            get: { plugin.isSelected },
            set: { newValue in
                sessionViewModel.updateExportPluginSelection(pluginID: plugin.id, isSelected: newValue)
            }
        )
    }

    private func updateCounts(from pluginData: [PluginExportTable.PluginData]) {
        let selectedData = pluginData.filter { $0.isSelected && $0.messageCount > 0 }
        selectedMessages = selectedData.reduce(0) { $0 + $1.messageCount }
        selectedPlugins = selectedData.count
    }

    private func showSavePanel() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "echoarchive") ?? UTType.data]
        savePanel.nameFieldStringValue = PluginMessageCache.defaultExportFilename()
        savePanel.title = "Save Plugin Data"
        savePanel.prompt = "Save"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                sessionViewModel.handleExport(url)
            }
        }
    }
}
