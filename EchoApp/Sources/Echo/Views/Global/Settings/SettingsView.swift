import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedSettingsTab")
    private var selectedSettingsTab = SettingsTab.general

    let appViewModel: AppViewModel

    var body: some View {
        TabView(selection: $selectedSettingsTab) {
            GeneralSettingsView(appViewModel: appViewModel)
                .tag(SettingsTab.general)
                .tabItem {
                    SettingsTab.general.tabItem
                }

            PluginsSettingsView(appViewModel: appViewModel)
                .tag(SettingsTab.plugins)
                .tabItem {
                    SettingsTab.plugins.tabItem
                }

            UpdatesSettingsView(appViewModel: appViewModel)
                .tag(SettingsTab.updates)
                .tabItem {
                    SettingsTab.updates.tabItem
                }
        }
        .frame(minHeight: 600)
        .tabViewStyle(.automatic)
    }
}

enum SettingsTab: Int {
    case general
    case plugins
    case updates

    var tabItem: SettingsTabButton {
        switch self {
        case .general:
            SettingsTabButton(imageName: "gear", title: "General")
        case .plugins:
            SettingsTabButton(imageName: "poweroutlet.type.b", title: "Plugins")
        case .updates:
            SettingsTabButton(imageName: "arrow.down.circle", title: "Updates")
        }
    }
}

struct SettingsTabButton: View {
    let imageName: String
    let title: String

    var body: some View {
        VStack {
            Image(systemName: imageName)
            Text(title)
        }
    }
}
