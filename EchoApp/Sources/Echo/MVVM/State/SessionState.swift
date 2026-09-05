import Combine
import EchoConnection
import EchoPluginAPI
import Foundation
import IdentifiedCollections
import SwiftUI

struct SessionState: Equatable, Identifiable {
    let id: UUID
    let port: Int
    let pluginManager: DesktopPluginManager
    
    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.id == rhs.id &&
        lhs.port == rhs.port &&
        lhs.currentScreen == rhs.currentScreen &&
        lhs.availableBonjourClients == rhs.availableBonjourClients &&
        lhs.availableADBClients == rhs.availableADBClients &&
        lhs.connectedClient == rhs.connectedClient &&
        lhs.lastConnectedClient == rhs.lastConnectedClient &&
        lhs.pendingConnectionClient == rhs.pendingConnectionClient &&
        lhs.loadedPlugins == rhs.loadedPlugins &&
        lhs.selectedPlugin == rhs.selectedPlugin &&
        lhs.collapsedSections == rhs.collapsedSections &&
        lhs.pluginsWithCachedData == rhs.pluginsWithCachedData &&
        lhs.isShowingClientSelector == rhs.isShowingClientSelector &&
        lhs.isShowingPluginQuickLaunchView == rhs.isShowingPluginQuickLaunchView &&
        lhs.exportState == rhs.exportState &&
        lhs.errorState == rhs.errorState &&
        lhs.adbError == rhs.adbError &&
        lhs.shouldAutoReconnect == rhs.shouldAutoReconnect &&
        lhs.initialClient == rhs.initialClient &&
        lhs.isImportedArchive == rhs.isImportedArchive &&
        lhs.archiveURL == rhs.archiveURL &&
        lhs.pendingDeepLink == rhs.pendingDeepLink &&
        lhs.autoConnectToFirstAvailable == rhs.autoConnectToFirstAvailable
    }
    
    // Navigation
    enum NavigationScreen: Equatable {
        case main           // Main plugin interface
        case clientPicker   // Client device picker screen
    }
    var currentScreen: NavigationScreen = .main
    
    var availableBonjourClients: [BonjourService] = []
    var availableADBClients: [ADB.Device] = []
    var connectedClient: ConnectedClient?
    var lastConnectedClient: DiscoveredClient?
    var pendingConnectionClient: DiscoveredClient?
    var shouldAutoReconnect: Bool = true
    var initialClient: DiscoveredClient?
    var isImportedArchive: Bool = false
    var archiveURL: URL?
    
    var pendingDeepLink: URL?
    var autoConnectToFirstAvailable: Bool = false
    var loadedPlugins: IdentifiedArrayOf<LoadedPlugin> = []
    var selectedPlugin: Identified<PluginIdentifier, LoadedPlugin>?
    var collapsedSections: [String] = UserDefaults.standard.collapsedSections ?? []
    var pluginsWithCachedData: Set<PluginIdentifier> = []
    
    var isShowingClientSelector: Bool = false
    var isShowingPluginQuickLaunchView: Bool = false
    var exportState: ExportState = .init()
    var errorState: ErrorState?
    var adbError: ADBError?
    
    var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    init(id: UUID = UUID(), port: Int, pluginManager: DesktopPluginManager) {
        self.id = id
        self.port = port
        self.pluginManager = pluginManager
    }
    
    // MARK: - Helper Methods
    
    func connectedClientHasPlugin(withID id: String) -> Bool {
        connectedClient?.clientInfo?.clientPluginIDs.contains(id) ?? false
    }
    
    // MARK: - Computed Properties
    
    var enabledPlugins: IdentifiedArrayOf<LoadedPlugin> {
        let plugins = enabledPluginsBySection.flatMap { sectionRef in
            sectionRef.plugins.elements
        }
        return IdentifiedArrayOf(uniqueElements: plugins)
    }
    
    var loadedPluginsBySection: IdentifiedArrayOf<SectionRef> {
        makeSectionsFromPlugins(plugins: loadedPlugins)
    }
    
    var enabledPluginsBySection: IdentifiedArrayOf<SectionRef> {
        let disabledPluginIdentifiers = UserDefaults.standard.disabledPluginIdentifiers ?? []
        return makeSectionsFromPlugins(
            plugins: loadedPlugins
                .filter { !disabledPluginIdentifiers.contains($0.id) }
        )
    }
    
    private func makeSectionsFromPlugins(plugins: IdentifiedArrayOf<LoadedPlugin>) -> IdentifiedArrayOf<SectionRef> {
        let sectionGroupingKey = UserDefaults.standard.sectionGroupingKey
        let sections: [SectionRef] = Dictionary(
            grouping: plugins,
            by: {
                switch sectionGroupingKey {
                case .category:
                    $0.plugin.metadata.category.name
                case .targetAppDisplayName:
                    $0.targetAppDisplayName ?? ""
                }
            }
        )
        .map { (id, plugins) in
            SectionRef(
                id: id,
                plugins: IdentifiedArray(
                    uniqueElements: plugins.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })
                )
            )
        }
        .sorted(by: { $0.id < $1.id })
        
        return IdentifiedArray(uniqueElements: sections)
    }
}

// MARK: - Supporting Types

struct ExportState: Equatable {
    var pluginData: [PluginExportTable.PluginData] = []
    var isShowingSavePanel: Bool = false
    var selectedPluginId: String? = nil
    var error: String? = nil
}

struct ErrorState: Equatable {
    let title: String
    let message: String
    let primaryButton: Button?
    let secondaryButton: Button?

    struct Button: Equatable {
        enum Action: Equatable {
            case dismiss
            case quit
            case restart
            case openURL(URL)
        }

        let title: String
        let action: Action
        let role: SwiftUI.ButtonRole?
    }

    static let okDismiss = Button(title: "OK", action: .dismiss, role: nil)

    init(
        title: String,
        message: String,
        primaryButton: Button? = nil,
        secondaryButton: Button? = nil
    ) {
        if primaryButton == nil && secondaryButton == nil {
            self.primaryButton = Self.okDismiss
            self.secondaryButton = nil
        } else {
            self.primaryButton = primaryButton
            self.secondaryButton = secondaryButton
        }
        self.title = title
        self.message = message
    }

    init(_ appError: AppError) {
        let combinedMessage = [appError.failureReason, appError.recoverySuggestion]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        
        self.init(
            title: appError.errorDescription ?? "Error",
            message: combinedMessage,
            primaryButton: appError.primaryButton,
            secondaryButton: appError.secondaryButton
        )
    }
}
