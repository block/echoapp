import Foundation
import EchoPluginAPI
import EchoConnection

@MainActor
struct SessionEnvironment {
    let server: Server
    let pluginManager: DesktopPluginManager
    let clientBrowser: BonjourBrowser
    let adbBrowser: ADBBrowser
    let adbProvider: () -> ADB?
    
    var applicationReloader: ApplicationReloader {
        ApplicationReloader()
    }
    
    var updateService: AppUpdateService {
        RealAppUpdateService()
    }
    
    init(server: Server, pluginManager: DesktopPluginManager) {
        self.server = server
        self.pluginManager = pluginManager
        self.adbProvider = ADB.sharedProvider
        self.clientBrowser = BonjourBrowser(serviceType: "_echoclient._tcp", adbProvider: adbProvider)
        self.adbBrowser = ADBBrowser(adbProvider: adbProvider)
    }
}
