import EchoClient
import SwiftUI

@main
struct App: SwiftUI.App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }
    }

    init() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

// MARK: -

@MainActor
struct MainView: View {
    var echoClient: EchoClient { .shared }
    var appInfoPlugin: AppInfoPlugin { echoClient.appInfoPlugin }

    var body: some View {
        VStack {
            startEchoClientButton
            stopEchoClientButton
            loadUnloadAppInfoPluginButton
        }
    }

    // MARK: -

    private var startEchoClientButton: some View {
        Button(
            action: { EchoClient.shared.start() },
            label: { Text("Start EchoClient") }
        )
    }

    private var stopEchoClientButton: some View {
        Button(
            action: { EchoClient.shared.stop() },
            label: { Text("Stop EchoClient") }
        )
    }

    private var loadUnloadAppInfoPluginButton: some View {
        Button(
            action: {
                if echoClient.plugin(with: appInfoPlugin.id) == nil {
                    EchoClient.shared.appInfoPlugin.setEntries(
                        [
                            .init(
                                scope: "Test Info",
                                key: "Plugin added at",
                                value: Date().ISO8601Format()
                            ),
                        ]
                    )
                    echoClient.addPlugin(appInfoPlugin)
                } else {
                    echoClient.removePlugin(appInfoPlugin)
                }
            },
            label: { Text("Load/unload AppInfoPlugin") }
        )
    }

}
