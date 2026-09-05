import AppKit
import Foundation
import EchoPluginAPI
import os

// MARK: - Loadable Plugins

protocol LoadablePlugin {
    var fileURL: URL { get }
    func load() -> [any DesktopPlugin]
}

struct FrameworkPlugin: LoadablePlugin {
    private let logger = Logger.echoLogger(category: "FrameworkPlugin")
    let fileURL: URL
    let bundleID: String

    init(fileURL: URL) {
        guard fileURL.pathExtension == "framework" else {
            fatalError("Expected framework file URL, got '\(fileURL)'")
        }
        guard let bundle = Bundle(url: fileURL) else {
            fatalError("\(fileURL) is missing an info.plist")
        }
        guard let bundleID = bundle.bundleIdentifier else {
            fatalError("Info.plist in \(fileURL) must have a bundle identifier")
        }
        self.fileURL = fileURL
        self.bundleID = bundleID
    }

    func load() -> [any DesktopPlugin] {
        logger.info("Loading '\(fileURL.absoluteString)'")

        guard
            let bundle = Bundle(url: fileURL),
            let executablePath = bundle.executablePath
        else {
            AnalyticsProvider.shared.trackPluginLoadFailed(
                type: "FrameworkPlugin",
                errorMessage: "Failed to load FrameworkPlugin. It was either not a bundle or did not contain an executable.",
                path: fileURL.absoluteString
            )
            return []
        }

        // All frameworks must be dynamic, thus they include a dylib which we can load.
        return DylibPlugin(fileURL: URL(fileURLWithPath: executablePath)).load()
    }
}

// MARK: -

struct DylibPlugin: LoadablePlugin {
    let fileURL: URL

    func load() -> [any DesktopPlugin] {
        func fail(reason: String) -> [any DesktopPlugin] {
            AnalyticsProvider.shared.trackPluginLoadFailed(
                type: "DylibPlugin",
                errorMessage: reason,
                path: fileURL.absoluteString
            )
            return []
        }

        guard let openResult: UnsafeMutableRawPointer = dlopen(fileURL.path, RTLD_NOW | RTLD_LOCAL) else {
            return fail(reason: dlerror().map { String(format: "%s", $0) } ?? "unknown")
        }

        defer {
            dlclose(openResult)
        }

        let symbolName = "makePluginProvider"
        guard let symbol = dlsym(openResult, symbolName) else {
            return fail(reason: "'\(symbolName)' symbol not found")
        }

        typealias InitFunction = @convention(c) () -> UnsafeMutableRawPointer
        let f = unsafeBitCast(symbol, to: InitFunction.self)
        let pluginProviderPointer = f()
        let pluginProvider = Unmanaged<PluginProvider>.fromOpaque(pluginProviderPointer).takeRetainedValue()
        
        return pluginProvider.providePluginTypes().map { $0.init() }
    }
}

// MARK: -

extension NSWorkspace {
    func open(_ pluginFramework: FrameworkPlugin) {
        let pluginDirectory = pluginFramework.fileURL.parentPathComponent(
            where: { $0.hasSuffix(".echoplugin") }
        )
        NSWorkspace.shared.open(pluginDirectory ?? pluginFramework.fileURL)
    }
}
