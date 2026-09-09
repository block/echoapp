#if os(iOS)

import AccessibilitySnapshotCore
import AccessibilitySnapshotParser
import Combine
import CryptoKit
import EchoPluginAPI
import Foundation
import UIKit

// MARK: - AccessibilityPlugin - Models

/*
 These data models are identical to the ones in the Echo Desktop Plugin.
 */

enum AccessibilityEvent: Codable {
    case requestSnapshot
    case snapshot(Snapshot)
    case sendLiveUpdates(Bool)
}

struct Snapshot: Codable {
    var imageData: Data
    var elements: [AccessibilityElement]
}

struct AccessibilityElement: Codable, Equatable {
    /// The description of the accessibility element that will be read by VoiceOver when the element is brought into
    /// focus.
    public var description: String

    /// A unique identifier for the element, primarily used in UI tests for locating and interacting with elements.
    /// This identifier is not visible to users.
    public var identifier: String?

    /// A hint that will be read by VoiceOver if focus remains on the element after the `description` is read.
    public var hint: String?

    /// The labels that will be used by Voice Control for user input.
    public var userInputLabels: [String]?

    /// The names of the custom actions supported by the element.
    public var customActions: [String]

    var frame: Rect
}

struct Rect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

// MARK: - AccessibilityPlugin

public final class AccessibilityPlugin: ClientPlugin {

    // MARK: - Public Properties

    public static let id: PluginIdentifier = "com.echo.plugin.accessibility"
    public var id: PluginIdentifier { Self.id }
    public let version = "0.0.1"

    // MARK: - Private Properties

    private var connection: PluginConnection?
    private var cancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var sendLiveUpdates: Bool = true

    // MARK: - Life Cycle

    public init() {}

    // MARK: - ClientPlugin

    public func onConnect(_ connection: EchoPluginAPI.PluginConnection) {
        self.connection = connection
        self.cancellable = connection
            .receive(AccessibilityEvent.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .requestSnapshot:
                    self.sendSnapshot()
                case .snapshot:
                    // Client Event
                    break
                case let .sendLiveUpdates(value):
                    self.sendLiveUpdates = value
                    if self.sendLiveUpdates {
                        startTimer()
                    } else {
                        stopTimer()
                    }
                }
            }
    }

    public func onDisconnect() {
        self.connection = nil
        self.cancellable = nil
        self.lastSnapshotHash = nil
    }

    public func onDesktopPluginActive() {
        if sendLiveUpdates {
            startTimer()
        }
    }

    public func onDesktopPluginInactive() {
        stopTimer()
    }

    // MARK: - Private Methods

    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendSnapshot()
            }
    }

    private func stopTimer() {
        timerCancellable = nil
    }

    private var lastSnapshotHash: String?

    private func sendSnapshot() {
        guard let connection, let viewController = UIApplication.shared.topMostViewController else {
            return
        }
        let imageData = viewController.snapshot()
        
        let currentSnapshotHash = generateImageHash(from: imageData)

        if let lastSnapshotHash, currentSnapshotHash == lastSnapshotHash {
            return
        }

        lastSnapshotHash = currentSnapshotHash

        let parser = AccessibilityHierarchyParser()
        let markers = parser.parseAccessibilityElements(in: viewController.view)

        let snapshot = Snapshot(
            imageData: imageData,
            elements: markers.map { marker in
                AccessibilityElement(
                    description: marker.description,
                    identifier: marker.identifier,
                    hint: marker.hint,
                    userInputLabels: marker.userInputLabels ?? [],
                    customActions: marker.customActions,
                    frame: {
                        switch marker.shape {
                        case let .frame(frame):
                            return Rect(
                                x: frame.midX,
                                y: frame.midY,
                                width: frame.width,
                                height: frame.height
                            )
                        case let .path(path):
                            let bounds = path.bezierPath.bounds
                            return Rect(
                                x: bounds.midX,
                                y: bounds.midY,
                                width: bounds.width,
                                height: bounds.height
                            )
                        }
                    }()
                )
            }
        )

        let event = AccessibilityEvent.snapshot(snapshot)
        try? connection.send(event)
    }

    /// Generate a hash of the image data
    private func generateImageHash(from data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: -

private extension UIView {
    func snapshot() -> Data {
        let renderer = UIGraphicsImageRenderer(size: self.bounds.size, format: .preferred())
        return renderer.jpegData(withCompressionQuality: 0.5) { context in
            self.drawHierarchy(in: self.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: -

private extension UIViewController {
    func snapshot() -> Data {
        view.snapshot()
    }
}

// MARK: -

private extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootViewController = windowScene.windows
                .first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }

        return topMostViewController(base: rootViewController)
    }

    func topMostViewController(base viewController: UIViewController) -> UIViewController {
        if let presentedVC = viewController.presentedViewController {
            return topMostViewController(base: presentedVC)
        }
        if let navigationController = viewController as? UINavigationController,
           let visibleVC = navigationController.visibleViewController {
            return topMostViewController(base: visibleVC)
        }
        if let tabBarController = viewController as? UITabBarController,
           let selectedVC = tabBarController.selectedViewController {
            return topMostViewController(base: selectedVC)
        }
        return viewController
    }
}

#endif
