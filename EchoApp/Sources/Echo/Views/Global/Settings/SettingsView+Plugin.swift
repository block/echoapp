import AppleArchive
import EchoPluginUI
import Foundation
import MarkdownUI
import SwiftUI

struct PluginsSettingsView: View {
    @AppStorage("MainSidebar.sectionGroupingKey") private var groupKey: MetadataGroupKey = .targetAppDisplayName
    @Environment(\.dismiss) private var dismiss

    @State var isInstalling = false
    @State var isDropTargetted = false
    @State var isAlertShown = false
    @State var installSuccessMessage: String?
    @State var installFailureMessage: String?

    @State var selectedPlugin: LoadedPlugin?

    let appViewModel: AppViewModel
    internal let pluginLocationProvider: DesktopPluginLocationProvider
    internal let fileManager: FileManager

    init(
        appViewModel: AppViewModel,
        pluginLocationProvider: DesktopPluginLocationProvider = .init(),
        fileManager: FileManager = .default
    ) {
        self.appViewModel = appViewModel
        self.pluginLocationProvider = pluginLocationProvider
        self.fileManager = fileManager
    }

    var body: some View {
        VStack {
            if isDropTargetted {
                PluginDragAndDropView(isInstalling: $isInstalling)
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        PluginSettingsSidebarView(
                            appViewModel: appViewModel,
                            selectedPlugin: $selectedPlugin
                        )
                        Divider()

                        if isInstalling {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.5)
                                    .padding()
                                Text("Installing plugins")
                                    .lineLimit(2, reservesSpace: true)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Plugin")
                                Spacer()
                                Text("Drag and drop .echoplugin or .zip")
                                    .font(.body)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                    .frame(maxWidth: 360, maxHeight: .infinity)

                    PluginSettingsDetailView(
                        appViewModel: appViewModel,
                        selectedPlugin: $selectedPlugin
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(
            of: [.directory, .zip],
            isTargeted: $isDropTargetted,
            perform: { providers in
                Task {
                    await handleDrop(providers: providers)
                }
                return true
            }
        )
        .alert(isPresented: $isAlertShown) {
            if let installSuccessMessage {
                Alert(
                    title: Text("Installation succeeded"),
                    message: Text(installSuccessMessage),
                    primaryButton: .destructive(Text("Reload plugins")) {
                        appViewModel.activeSession?.restart()
                        dismiss()
                    },
                    secondaryButton: .default(Text("Reload later"))
                )
            } else {
                Alert(
                    title: Text("Installation failed"),
                    message: installFailureMessage.map(Text.init)
                )
            }
        }
        .onAppear {
            AnalyticsProvider.shared.trackPluginSettingsViewed()
        }
    }
}

struct PluginSectionHeader: View {
    let sectionRef: SectionRef
    let sessionViewModel: SessionViewModel

    var body: some View {
        HStack {
            Text(sectionRef.id)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Hide All") {
                    sessionViewModel.updatePluginVisibility(Array(sectionRef.plugins.ids), shouldShow: false)
                }
                Button("Show All") {
                    sessionViewModel.updatePluginVisibility(Array(sectionRef.plugins.ids), shouldShow: true)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.bar)
        .frame(maxWidth: .infinity)
    }
}

struct PluginSettingsSidebarView: View {
    @AppStorage("MainSidebar.sectionGroupingKey") private var groupKey: MetadataGroupKey = .targetAppDisplayName
    @State var searchText: String = ""

    let appViewModel: AppViewModel
    @Binding var selectedPlugin: LoadedPlugin?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            pluginCountAndPicker
            Divider()
            pluginsListView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.disabledControlText)
            TextField("Search", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(5)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(.bar)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
        .padding(8)
    }

    @ViewBuilder
    private var pluginCountAndPicker: some View {
        if let session = appViewModel.activeSession {
            HStack(alignment: .center) {
                let count = session.loadedPlugins.filter { isPluginIncluded(plugin: $0) }.count
                Text("\(count) plugin\(count == 1 ? "" : "s")")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
                Spacer()
                Picker("By", selection: $groupKey) {
                    ForEach(MetadataGroupKey.allCases, id: \.rawValue) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: 140)
                .pickerStyle(.menu)
                .tint(Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(minWidth: 200)
            .padding(.init(top: 0, leading: 16, bottom: 8, trailing: 8))
        }
    }

    @ViewBuilder
    private var pluginsListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let session = appViewModel.activeSession {
                    ForEach(session.loadedPluginsBySection) { sectionRef in
                        let filteredPlugins = sectionRef.plugins.filter { isPluginIncluded(plugin: $0) }
                        if !filteredPlugins.isEmpty {
                            PluginSectionHeader(sectionRef: sectionRef, sessionViewModel: session)
                                .background(.bar)
                            ForEach(filteredPlugins) { plugin in
                                PluginDetailRow(
                                    sessionViewModel: session,
                                    plugin: plugin,
                                    isSelected: plugin == selectedPlugin
                                )
                                .onTapGesture {
                                    selectedPlugin = plugin
                                }
                                Divider().padding(0)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isPluginIncluded(plugin: LoadedPlugin) -> Bool {
        guard !searchText.isEmpty else { return true }
        return plugin.displayName.localizedCaseInsensitiveContains(searchText)
            || plugin.description.localizedCaseInsensitiveContains(searchText)
            || plugin.category.name.localizedCaseInsensitiveContains(searchText)
    }
}

struct PluginSettingsDetailView: View {
    let appViewModel: AppViewModel
    @Binding var selectedPlugin: LoadedPlugin?

    private func loadReadme(for plugin: LoadedPlugin) -> String? {
        if let framework = plugin.framework,
           let bundle = Bundle(url: framework.fileURL),
           let readmePath = bundle.path(forResource: "README", ofType: "md"),
           let content = try? String(contentsOfFile: readmePath, encoding: .utf8) {
            return content
        }

        let targetName = String(describing: type(of: plugin.plugin)).replacingOccurrences(of: ".", with: "_")
        let bundleName = "echo_\(targetName)"

        if let bundleURL = Bundle.main.resourceURL?.appending(path: "\(bundleName).bundle"),
           let bundle = Bundle(url: bundleURL),
           let readmePath = bundle.path(forResource: "README", ofType: "md"),
           let content = try? String(contentsOfFile: readmePath, encoding: .utf8) {
            return content
        }

        return nil
    }

    var body: some View {
        if let selectedPlugin {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        VStack {
                            selectedPlugin.icon
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8.0).fill(Color.blue))

                        VStack(alignment: .leading) {
                            Text(selectedPlugin.displayName)
                                .font(.title)
                                .bold()
                            Text(selectedPlugin.id)
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .bold()
                                .textSelection(.enabled)
                        }

                        Spacer()

                        VStack {
                            Spacer()
                            if selectedPlugin.framework != nil {
                                Button("Open in Finder") {
                                    appViewModel.activeSession?.openPluginInFinder(selectedPlugin.id)
                                }
                                .buttonStyle(BorderedButtonStyle())
                            }
                        }
                    }
                    .padding(16)
                    Divider()

                    if let readmeContent = loadReadme(for: selectedPlugin) {
                        Markdown(readmeContent)
                            .markdownTheme(.gitHub)
                            .padding(16)
                            .background(Theme.gitHub.textBackgroundColor)
                            .textSelection(.enabled)
                    } else {
                        HStack {
                            Text(selectedPlugin.description)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(16)
                    }
                }
            }
        } else {
            VStack {
                Text("Select a plugin")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PluginDetailRow: View {
    let sessionViewModel: SessionViewModel
    let plugin: LoadedPlugin
    let isSelected: Bool

    var body: some View {
        let isEnabled = sessionViewModel.enabledPlugins.contains(plugin)

        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                Text(plugin.displayName)
                    .bold()
                Text(plugin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Text("v\(plugin.version) - \(plugin.category.name) - \(plugin.plugin.metadata.orgDisplayName)")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                sessionViewModel.updatePluginVisibility([plugin.id], shouldShow: !isEnabled)
            } label: {
                Image(systemName: isEnabled ? "eye.fill" : "eye.slash.fill")
            }
            .buttonStyle(PlainButtonStyle())
        }
        .opacity(isEnabled ? 1.0 : 0.33)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : Color(white: 0.0, opacity: 0.01))
    }
}
