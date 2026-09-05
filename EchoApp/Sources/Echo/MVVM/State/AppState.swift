import Combine
import EchoConnection
import EchoPluginAPI
import Foundation
import SwiftUI

struct AppState: Equatable {
    var sectionGroupingKey: MetadataGroupKey = UserDefaults.standard.sectionGroupingKey
    var disabledPluginIdentifiers: [PluginIdentifier] = UserDefaults.standard.disabledPluginIdentifiers ?? []

    var debuggerState: DebuggerState = .init()

    /// Pending deep links queued before any session exists (cold launch path).
    var pendingDeepLinkURLs: [URL] = []

    /// Firewall state (global)
    enum FirewallState: Equatable {
        case unknown
        case known(exceptionsEnabled: Bool)
    }
    var firewallState: FirewallState = .unknown

    struct UpdateState: Equatable {
        var isCheckingForUpdates: Bool = false
        var availableUpdate: Release? = nil
        var updateError: String? = nil
        var showingUpdateAlert: UpdateAlert? = nil

        enum UpdateAlert: Equatable {
            case noUpdatesAvailable
            case updateError(String)
            case updateRedirect(message: String, buttonTitle: String, url: String)
        }
    }
    var updateState: UpdateState = .init()

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        lhs.sectionGroupingKey == rhs.sectionGroupingKey &&
        lhs.disabledPluginIdentifiers == rhs.disabledPluginIdentifiers &&
        lhs.debuggerState == rhs.debuggerState &&
        lhs.pendingDeepLinkURLs == rhs.pendingDeepLinkURLs &&
        lhs.firewallState == rhs.firewallState &&
        lhs.updateState == rhs.updateState
    }
}

struct DebuggerState: Equatable {
    var incomingPluginPayloadsCancellable: AnyCancellable?
    var debugPayloads: [DebugPayload] = []
    var searchText: String = ""
    var isEnabled: Bool = false
    var messageLimit: Int = 500
    var selectedPluginFilter: String? = nil // nil means "All Plugins"
    var isPaused: Bool = false
    var selectedPayloadId: UUID? = nil

    var availablePluginIds: [String] {
        Array(Set(debugPayloads.map { $0.pluginID })).sorted()
    }

    var filteredPayloads: [DebugPayload] {
        var filtered = debugPayloads

        // Apply plugin filter first
        if let selectedPlugin = selectedPluginFilter {
            filtered = filtered.filter { $0.pluginID == selectedPlugin }
        }

        // Apply search text filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.pluginID.localizedCaseInsensitiveContains(searchText) ||
                $0.prettyData.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply message limit (take most recent messages)
        if filtered.count > messageLimit {
            filtered = Array(filtered.prefix(messageLimit))
        }

        return filtered
    }

    var selectedPayload: DebugPayload? {
        guard let selectedPayloadId = selectedPayloadId else { return nil }
        return debugPayloads.first { $0.id == selectedPayloadId }
    }
}
