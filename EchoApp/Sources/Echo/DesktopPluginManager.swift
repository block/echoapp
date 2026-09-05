import AccessibilityDesktopPlugin
import AnalyticsDesktopPlugin
import AppInfoDesktopPlugin
import AppKit
import CrashReportingDesktopPlugin
import DebugMenuDesktopPlugin
import EchoPluginAPI
import Foundation
import KeyValueStoreDesktopPlugin
import LoggingDesktopPlugin
import NavigationDesktopPlugin
import NetworkingDesktopPlugin
import SwiftUI

final class DesktopPluginManager {

    // MARK: - Private Properties

    private let pluginFrameworks: any Sequence<FrameworkPlugin>

    // MARK: - Life Cycle

    init(
        pluginFrameworks: any Sequence<FrameworkPlugin>
    ) {
        self.pluginFrameworks = pluginFrameworks
    }

    // MARK: - Public Methods

    func makePlugins() -> some Collection<LoadedPlugin> {
        let staticPlugins: [DesktopPlugin] = [
            AnalyticsDesktopPlugin(),
            AppInfoDesktopPlugin(),
            LoggingDesktopPlugin(),
            KeyValueStoreDesktopPlugin(),
            NetworkingDesktopPlugin(),
            AccessibilityDesktopPlugin(),
            NavigationDesktopPlugin(),
            DebugMenuDesktopPlugin(),
            CrashReportingDesktopPlugin(),
        ]

        let dynamicPlugins = pluginFrameworks.flatMap { framework in
            framework.load().map { plugin in
                LoadedPlugin(framework: framework, plugin: plugin)
            }
        }

        return dynamicPlugins + staticPlugins.map {
            LoadedPlugin(framework: nil, plugin: $0)
        }
    }
}
