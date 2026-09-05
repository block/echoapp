import Foundation
import EchoPluginAPI

/// Global app environment shared across all sessions.
struct AppEnvironment {
    let applicationReloader: ApplicationReloader
    let firewallDaemon: FirewallDaemon
    let pluginLocationProvider: DesktopPluginLocationProvider
    let updateService: AppUpdateService
    let pluginFrameworks: [FrameworkPlugin]
    
    init(
        applicationReloader: ApplicationReloader = ApplicationReloader(),
        firewallDaemon: FirewallDaemon = RealFirewallDaemon(),
        pluginLocationProvider: DesktopPluginLocationProvider = .init(),
        updateService: AppUpdateService = RealAppUpdateService(),
        pluginFrameworks: [FrameworkPlugin] = []
    ) {
        self.applicationReloader = applicationReloader
        self.firewallDaemon = firewallDaemon
        self.pluginLocationProvider = pluginLocationProvider
        self.updateService = updateService
        self.pluginFrameworks = pluginFrameworks
    }
} 
