import SwiftUI

// MARK: -

struct SidebarView: View {
    @AppStorage("MainSidebar.hideInactivePlugins") private var hideInactivePlugins = false
    @Environment(\.openWindow) var openWindow

    let pluginManager: DesktopPluginManager
    let sessionViewModel: SessionViewModel
    let availableUpdate: Release?
    let onInstallUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if availableUpdate != nil {
                UpdateNotificationBannerContainer(
                    availableUpdate: availableUpdate,
                    onInstall: onInstallUpdate
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            if sessionViewModel.isImportedArchive {
                ArchiveButton(archiveURL: sessionViewModel.archiveURL)
                    .padding(.horizontal, 10)
            } else {
                ClientChooserButton(sessionViewModel: sessionViewModel)
                    .padding(.horizontal, 10)
            }

            Spacer()
                .frame(height: 10)
            List(
                selection: Binding(
                    get: { sessionViewModel.selectedPlugin?.id },
                    set: { sessionViewModel.selectPlugin($0) }
                )
            ) {
                ForEach(sessionViewModel.enabledPluginsBySection) { sectionRef in
                    let plugins = sectionRef.plugins.filter { plugin in
                        if sessionViewModel.isImportedArchive {
                            return sessionViewModel.pluginsWithCachedData.contains(plugin.id)
                        } else if hideInactivePlugins {
                            return plugin.desktopOnly || sessionViewModel.state.connectedClientHasPlugin(withID: plugin.id)
                        } else {
                            return true
                        }
                    }
                    if !plugins.isEmpty {
                        SidebarSection(title: sectionRef.id, sessionViewModel: sessionViewModel, plugins: plugins)
                    }
                }
            }
            Divider()
            FooterView(sessionViewModel: sessionViewModel)
        }
    }
}

struct FooterView: View {
    @State private var showingResetPluginAlert = false

    @AppStorage("selectedSettingsTab")
    private var selectedSettingsTab = SettingsTab.general

    let sessionViewModel: SessionViewModel

    var body: some View {
        HStack {
            Button(
                action: {
                    showingResetPluginAlert = true
                },
                label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            )
            .buttonStyle(.borderless)
            .help("Reset plugins")
            .alert(
                isPresented: $showingResetPluginAlert,
                content: resetPluginsConfirmationAlert
            )
            Spacer()
            SettingsLink {
                Image(systemName: "gear")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Plugin settings")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private func resetPluginsConfirmationAlert() -> Alert {
        .init(
            title: Text("Disconnect & Reload Plugins?"),
            message: Text("All of the plugin content will be wiped and you'll be prompted to reconnect your client afterwards."),
            primaryButton: .destructive(Text("Reset")) {
                sessionViewModel.resetPlugins()
            },
            secondaryButton: .cancel()
        )
    }
}

struct SidebarHeader: View {

    let title: String
    let isAvailable: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
                .bold()
                .foregroundColor(isAvailable ? .secondary : .tertiaryLabel)
        }
        .padding(.vertical, 2)
    }
}

struct SidebarSection: View {
    @Environment(\.openWindow) var openWindow
    @State var isExpanded = true

    let title: String
    let sessionViewModel: SessionViewModel
    let plugins: any Collection<LoadedPlugin>

    var body: some View {
        Section(
            isExpanded: Binding(
                get: { !sessionViewModel.collapsedSections.contains(title) },
                set: { isExpanded in
                    sessionViewModel.collapseSection(shouldCollapse: !isExpanded, section: title)
                }
            )
        ) {
            ForEach(
                plugins.sorted(by: { first, second in
                    first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
                }),
                id: \.id
            ) { plugin in
                makeCell(for: plugin)
            }
        } header: {
            makeSectionHeader()
        }
    }

    private func makeSectionHeader() -> some View {
        let isAnyPluginAvailable: Bool = {
            if sessionViewModel.isImportedArchive {
                return plugins.first { sessionViewModel.pluginsWithCachedData.contains($0.id) } != nil
            } else {
                return plugins.first { $0.desktopOnly || sessionViewModel.state.connectedClientHasPlugin(withID: $0.id) } != nil
            }
        }()

        return Group {
            if !title.isEmpty {
                HStack {
                    SidebarHeader(title: title, isAvailable: isAnyPluginAvailable)
                    Spacer()
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        sessionViewModel.updatePluginVisibility(Array(plugins.map(\.id)), shouldShow: false)
                    } label: {
                        Text("Hide all \(title) plugins")
                    }
                }
            }
        }
    }

    private func makeCell(for plugin: LoadedPlugin) -> some View {
        let isSelected: Bool = plugin.id == sessionViewModel.selectedPlugin?.id

        let isAvailable: Bool = {
            if sessionViewModel.isImportedArchive {
                return sessionViewModel.pluginsWithCachedData.contains(plugin.id)
            } else {
                let isDesktopOnly = plugin.plugin.metadata.desktopOnly
                return isDesktopOnly || sessionViewModel.state.connectedClientHasPlugin(withID: plugin.id)
            }
        }()

        return PluginListCell(plugin: plugin, isAvailable: isAvailable, isSelected: isSelected)
            .contextMenu {
                Button {
                    openWindow(id: WindowID.plugin, value: plugin.id)
                } label: {
                    Text("Open in New Window")
                }
                Button {
                    sessionViewModel.updatePluginVisibility([plugin.id], shouldShow: false)
                } label: {
                    Text("Hide")
                }
            }
    }
}

// MARK: -

struct PluginListCell: View {
    @AppStorage("MainSidebar.dimInactivePlugins") private var dimInactivePlugins = true
    @AppStorage("MainSidebar.showMessageCount") private var showMessageCount = true

    let plugin: LoadedPlugin
    let isAvailable: Bool
    var isSelected: Bool

    var shouldDimPluginCell: Bool {
        dimInactivePlugins && !isAvailable
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            plugin.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundColor(shouldDimPluginCell ? Color(NSColor.disabledControlTextColor) : .accentColor)
                .scaledToFit()
            Text(plugin.displayName)
                .font(Font.body)
                .foregroundColor(shouldDimPluginCell ? Color(NSColor.disabledControlTextColor) : .primary)
                .help("\(plugin.description)\nVersion: [\(plugin.version)]")
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .cornerRadius(10)
    }
}

// MARK: - Archive Button

struct ArchiveButton: View {
    let archiveURL: URL?

    var body: some View {
        Button(action: revealInFinder) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(archiveName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("Archived Data")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help("Reveal archive in Finder")
    }

    private var archiveName: String {
        archiveURL?.deletingPathExtension().lastPathComponent ?? "Unknown Archive"
    }

    private func revealInFinder() {
        guard let url = archiveURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
