import AppKit
import Combine
import EchoConnection
import EchoPluginAPI
import Foundation
import SwiftUI

public struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let appViewModel: AppViewModel
    private let startupError: String?

    public init() {
        EchoAppDefaultsMigration.migrateIfNeeded()

        // Load plugin frameworks
        let pluginFrameworks: [FrameworkPlugin]
        let errorMessage: String?
        do {
            pluginFrameworks = try Array(FrameworkPluginLoader().loadPluginFrameworks())
            errorMessage = nil
        } catch {
            pluginFrameworks = []
            errorMessage = "Failed to load plugin frameworks: \(error)"
        }
        self.startupError = errorMessage
        
        self.appViewModel = AppViewModel(pluginFrameworks: pluginFrameworks)
        appDelegate.appViewModel = appViewModel
    }

    public var body: some Scene {
        WindowGroup(for: SessionWindow.self) { $session in
            let sessionId = session?.id ?? UUID()
            EchoSessionView(sessionId: sessionId, appViewModel: appViewModel, startupError: startupError)
                .id(sessionId)
                .updateAlerts(appViewModel: appViewModel)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    appViewModel.startCLISessionMonitoring()
                }
                .onDisappear {
                    appViewModel.destroySession(sessionId)
                }
        }
        .commands {
            EchoMenuBarCommands(appViewModel: appViewModel)
            ExportPluginDataCommand(appViewModel: appViewModel)
        }
        
        WindowGroup(id: WindowID.plugin, for: PluginIdentifier.self) { $pluginID in
            PluginPopoutWindow(appViewModel: appViewModel, pluginID: $pluginID)
        }
        
        Window("Payload Debugger", id: WindowID.payloadDB) {
            DebugPayloadView(appViewModel: appViewModel)
        }

        Settings {
            SettingsView(appViewModel: appViewModel)
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Application delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appViewModel: AppViewModel?

    override init() {
        super.init()
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    
    // Handle incoming URLs
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let appViewModel else { return }

        NSApp.activate(ignoringOtherApps: true)

        if let session = appViewModel.activeSession ?? appViewModel.sessions.values.first {
            for url in urls {
                if url.scheme == "echo" {
                    session.handleDeepLink(url)
                } else if url.pathExtension == "echoarchive" {
                    let appErr = PluginLoaderError.failedToCreatePluginsDirectory(url, NSError())
                    session.showError(ErrorState(appErr))
                }
            }
        } else {
            // Queue deep links for cold-launch scenarios until first session is created.
            let echoURLs = urls.filter { $0.scheme == "echo" }
            if !echoURLs.isEmpty {
                appViewModel.enqueuePendingDeepLinks(echoURLs)
            }
        }
    }
}
