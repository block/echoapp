import Foundation
import SwiftUI

protocol AppError: LocalizedError {
    var primaryButton: ErrorState.Button { get }
    var secondaryButton: ErrorState.Button? { get }
}

enum ConnectionError: AppError {
    case connectFailed(context: String, underlyingError: Error)
    case sendFailed(context: String, underlyingError: String)
    case decodeFailed(context: String, underlyingError: String)
    case browseFailed(underlyingError: String)

    var errorDescription: String? {
        switch self {
        case .connectFailed: "Client Connection Failed"
        case .sendFailed: "Send Failed"
        case .decodeFailed: "Data Parse Failed"
        case .browseFailed: "Client Discovery Failed"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .connectFailed(context, underlyingError):
            """
            Echo was unable to establish a connection.

            Context: \(context)
            Error: \(underlyingError.localizedDescription)

            Try:
            • Ensure the device or simulator is running and on the same network
            • Disconnect and reconnect the client from Echo
            """
        case let .sendFailed(context, underlyingError):
            """
            Echo was unable to send data to the connected client.

            Context: \(context)
            Error: \(underlyingError)

            Try:
            • Ensure the client app is running and connected
            • Disconnect and reconnect the client
            """
        case let .decodeFailed(context, underlyingError):
            """
            Echo received data it could not parse.

            Context: \(context)
            Error: \(underlyingError)

            Try:
            • Ensure the client and Echo app versions are compatible
            • Reconnect the client and retry the action
            """
        case let .browseFailed(underlyingError):
            """
            Echo failed while browsing for clients via Bonjour.

            Error: \(underlyingError)

            Try:
            • Ensure your network allows Bonjour/mDNS discovery
            • Restart Echo and your client app
            • If on macOS 15.4-15.5, start Echo before launching the iOS Simulator
            """
        }
    }

    var failureReason: String? {
        switch self {
        case let .connectFailed(context, underlyingError):
            "Failed to connect (\(context)): \(underlyingError.localizedDescription)"
        case let .sendFailed(context, underlyingError):
            "Failed to send data (\(context)): \(underlyingError)"
        case let .decodeFailed(context, underlyingError):
            "Failed to decode data (\(context)): \(underlyingError)"
        case let .browseFailed(underlyingError):
            "Failed to browse for clients: \(underlyingError)"
        }
    }

    var primaryButton: ErrorState.Button { ErrorState.okDismiss }
    var secondaryButton: ErrorState.Button? { nil }
}

enum ADBError: Error, Equatable {
    case adbNotFound
    case adbDiscoveryFailed(underlyingError: String)
    case adbCommandFailed(command: String, underlyingError: String)

    var errorDescription: String {
        switch self {
        case .adbNotFound: "Android ADB Not Installed"
        case .adbDiscoveryFailed: "Android ADB Device Discovery Failed"
        case .adbCommandFailed: "Android ADB command failed"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .adbNotFound:
            """
            `brew install android-platform-tools`
            """
        case .adbDiscoveryFailed, .adbCommandFailed:
            nil
        }
    }

    var failureReason: String? {
        switch self {
        case .adbNotFound:
            nil
        case let .adbDiscoveryFailed(underlyingError):
            "EchoApp encountered an error while searching for Android devices via `adb devices`\n\(underlyingError)"
        case let .adbCommandFailed(command, underlyingError):
            "EchoApp encountered an error while executing `adb \(command)`: \(underlyingError)"
        }
    }

    var completeErrorDescription: String {
        var components: [String] = [errorDescription]
        if let failureReason {
            components.append(failureReason)
        }
        if let recoverySuggestion {
            components.append(recoverySuggestion)
        }
        return components.joined(separator: "\n")
    }

}

struct ConnectionConfirmationError: LocalizedError, Equatable {
    var errorDescription: String? {
        "The requested client connection was replaced before EchoApp could take ownership of it."
    }
}

enum PluginLoaderError: AppError {
    case failedToCreatePluginsDirectory(URL, Error)

    var errorDescription: String? {
        switch self {
        case let .failedToCreatePluginsDirectory(url, underlying):
            "Failed to create Plugins directory at '\(url)'. Reason: \(underlying.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .failedToCreatePluginsDirectory(url, _):
            """
            Echo could not create the Plugins directory at the expected Application Support location:

            \(url.path)

            Try:
            • Ensure you have write permissions to Application Support
            • Remove any file at that path that is not a directory
            • Restart Echo
            """
        }
    }
    
    var failureReason: String? {
        switch self {
        case let .failedToCreatePluginsDirectory(url, underlying):
            "Failed to create Plugins directory at '\(url)'. Reason: \(underlying.localizedDescription)"
        }
    }

    var primaryButton: ErrorState.Button { ErrorState.okDismiss }
    var secondaryButton: ErrorState.Button? { nil }
}

enum LifecycleError: AppError {
    case serverStartFailed(underlyingError: String)

    var recoverySuggestion: String? {
        switch self {
        case let .serverStartFailed(underlyingError):
            """
            Multiple EchoApp.app instances may be running.

            Error: \(underlyingError)

            Try:
            • Quit all EchoApp.app instances
            • Restart Echo
            """
        }
    }

    var errorDescription: String? { "Failed to start EchoApp Server" }
    var failureReason: String? { nil }
    var primaryButton: ErrorState.Button { .init(title: "Quit", action: .quit, role: .destructive) }
    var secondaryButton: ErrorState.Button? { nil }
}

// MARK: - Firewall Errors

enum FirewallError: AppError {
    case stateError(Error)
    case toggleFailed(Error)

    var errorDescription: String? {
        switch self {
        case .stateError:
            "Firewall State Error"
        case .toggleFailed:
            "Firewall Toggle Failed"
        }
    }

    var failureReason: String? {
        switch self {
        case let .stateError(error):
            error.localizedDescription
        case let .toggleFailed(error):
            error.localizedDescription
        }
    }

    var recoverySuggestion: String? { nil }
    var primaryButton: ErrorState.Button { ErrorState.okDismiss }
    var secondaryButton: ErrorState.Button? { nil }
}

// MARK: - Client Errors

enum ClientError: AppError {
    case clientDiscoveryFailed(Error)
    case connectionRequestFailed(clientName: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .clientDiscoveryFailed:
            "Client Discovery Failed"
        case let .connectionRequestFailed(clientName, _):
            "Failed to connect to \(clientName)"
        }
    }

    var failureReason: String? {
        switch self {
        case let .clientDiscoveryFailed(error), let .connectionRequestFailed(_, error):
            return (error as? AppError)?.failureReason ?? error.localizedDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .clientDiscoveryFailed(error), let .connectionRequestFailed(_, error):
            return (error as? AppError)?.recoverySuggestion
        }
    }

    var primaryButton: ErrorState.Button { ErrorState.okDismiss }
    var secondaryButton: ErrorState.Button? { nil }
}

struct ConnectionRequestTimeoutError: AppError {
    let seconds: TimeInterval

    var errorDescription: String? {
        "Connection Request Timed Out"
    }

    var failureReason: String? {
        "The client did not accept the Echo connection request within \(Int(seconds.rounded())) seconds."
    }

    var recoverySuggestion: String? {
        """
        Try:
        • Make sure the client app is still running
        • Check that the device is reachable on the same network
        • Tap the device again to retry
        """
    }

    var primaryButton: ErrorState.Button { ErrorState.okDismiss }
    var secondaryButton: ErrorState.Button? { nil }
}

// MARK: - Plugin Errors

enum PluginError: AppError {
    case sendFailed(context: String, underlyingError: Error)

    var errorDescription: String? { "Send Failed" }

    var failureReason: String? {
        switch self {
        case let .sendFailed(context, underlyingError):
            "Failed to send data (\(context)): \(underlyingError.localizedDescription)"
        }
    }

    var recoverySuggestion: String? { nil }
    var primaryButton: ErrorState.Button { ErrorState.okDismiss }
    var secondaryButton: ErrorState.Button? { nil }
}
