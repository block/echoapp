import Foundation
import SwiftUI

struct EchoMenuBarCommands: Commands {
    @Environment(\.openWindow) var openWindow

    @AppStorage("selectedSettingsTab")
    private var selectedSettingsTab = SettingsTab.general

    let pluginLocationProvider: DesktopPluginLocationProvider
    let fileManager: FileManager
    let appViewModel: AppViewModel

    init(
        pluginLocationProvider: DesktopPluginLocationProvider = .init(),
        fileManager: FileManager = .default,
        appViewModel: AppViewModel
    ) {
        self.pluginLocationProvider = pluginLocationProvider
        self.fileManager = fileManager
        self.appViewModel = appViewModel
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                openWindow(value: SessionWindow(id: UUID()))
            } label: {
                Label("New Session", systemImage: "macwindow.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                appViewModel.checkForUpdates()
            }
            .keyboardShortcut("u", modifiers: [.command])
            Divider()
        }

        CommandMenu("Navigate") {
            if let session = appViewModel.activeSession {
                Button("Quick Launch") {
                    session.showQuickLaunchPanel(true)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()

                Button("Previous Plugin") {
                    session.selectPreviousPlugin()
                }
                .keyboardShortcut("{", modifiers: [.command])

                Button("Next Plugin") {
                    session.selectNextPlugin()
                }
                .keyboardShortcut("}", modifiers: [.command])
            }
        }

        CommandMenu("Plugins") {
            SettingsLink {
                Text("Manage Plugins")
            }
            Divider()

            if let session = appViewModel.activeSession {
                Button("Reload Plugins") {
                    session.restart()
                }

                Button("Open Install Location") {
                    session.openURL(pluginLocationProvider.applicationSupport())
                }
                Divider()

                if let plugin = session.selectedPlugin?.value {
                    Button("Open \(plugin.displayName) in New Window") {
                        openWindow(id: WindowID.plugin, value: plugin.id)
                    }
                    .keyboardShortcut("t", modifiers: [.command])
                }
            }

            Button("Payload Debugger") {
                openWindow(id: WindowID.payloadDB)
            }
        }
    }
}
