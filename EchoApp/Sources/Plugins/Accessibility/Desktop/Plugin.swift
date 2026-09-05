import AppKit
import Combine
import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public final class AccessibilityDesktopPlugin: DesktopPlugin {

    // MARK: - Public Properties

    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)

    // MARK: - Private Properties

    private let viewModel: AccessibilityViewModel

    // MARK: - Life Cycle

    public init() {
        self.viewModel = .init(connection: .init(nil))
    }

    // MARK: - DesktopPlugin

    public func makeView() -> AnyView {
        return AnyView(
            AccessibilityView(viewModel: viewModel)
        )
    }

    public func onConnect(_ connection: PluginConnection) {
        self.viewModel.connect(connection: connection)
    }

    public func onDisconnect() {
        self.viewModel.disconnect()
    }
}
