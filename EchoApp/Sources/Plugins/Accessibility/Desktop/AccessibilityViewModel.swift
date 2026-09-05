import Combine
import EchoPluginAPI
import EchoPluginUI
import Foundation
import SwiftUI

public final class AccessibilityViewModel: ObservableObject {

    private let connection: CurrentValueSubject<PluginConnection?, Never>
    private var cancellable: AnyCancellable?

    public init(connection: CurrentValueSubject<PluginConnection?, Never>) {
        self.connection = connection
    }

    // MARK: - Published Value

    @Published var currentSnapshot: Snapshot?
    @Published var position: CGSize = .zero
    @Published var initialScale: CGFloat?
    @Published var scale: CGFloat = 1.0
    @Published var selectedAccessibilityElement: AccessibilityElement?
    @Published var sendLiveUpdates: Bool = true {
        didSet {
            sendLiveUpdates(sendLiveUpdates)
        }
    }

    // MARK: - Constants

    struct Toolbar {
        static let height: CGFloat = 32
        static let sliderWidth: CGFloat = 200
        static let sliderRange: ClosedRange<CGFloat> = 0.25...10.0
    }

    // MARK: - Computed Properties

    public var scalePercentage: String {
        String(format: "%.0f%%", scale * 100)
    }

    public var sendLiveUpdatesBinding: Binding<Bool> {
        .init { [unowned self] in
            self.sendLiveUpdates
        } set: { [unowned self] newValue in
            self.sendLiveUpdates = newValue
        }
    }

    // MARK: - Public Methods

    public func takeSnapshot() {
        try? connection.value?.send(AccessibilityEvent.requestSnapshot)
    }

    public func launchAccessibilityInspector() {
        let bundleIdentifier = "com.apple.AccessibilityInspector"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.open(appURL)
        }
    }

    public func sendLiveUpdates(_ value: Bool) {
        try? connection.value?.send(AccessibilityEvent.sendLiveUpdates(value))
    }

    public func resetView() {
        position = .zero
        scale = 1.0
    }

    public func isSelected(_ element: AccessibilityElement) -> Bool {
        selectedAccessibilityElement == element
    }

    // MARK: - Snapshot Scaling

    public struct ScaleData {
        let scale: CGFloat
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        let xOffset: CGFloat
        let yOffset: CGFloat
    }

    public func calculateScaleData(for image: NSImage, in size: CGSize) -> ScaleData {
        let scaleWidth = size.width / image.size.width
        let scaleHeight = size.height / image.size.height
        let calculatedScale = min(scaleWidth, scaleHeight)

        let imageWidth = image.size.width * calculatedScale
        let imageHeight = image.size.height * calculatedScale

        let xOffset = (size.width - imageWidth) / 2
        let yOffset = (size.height - imageHeight) / 2

        return ScaleData(
            scale: calculatedScale,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            xOffset: xOffset,
            yOffset: yOffset
        )
    }

    // MARK: - Connection

    public func connect(connection: PluginConnection) {
        self.connection.value = connection
        cancellable = connection
            .receive(AccessibilityEvent.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .requestSnapshot,
                        .sendLiveUpdates:
                    // Server Events
                    break
                case let .snapshot(snapshot):
                    self?.currentSnapshot = snapshot
                }
            }
        sendLiveUpdates(sendLiveUpdates)
    }

    public func disconnect() {
        cancellable = nil
    }
}
