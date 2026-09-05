import Foundation

/// Provides the standard locations for plugins.
struct DesktopPluginLocationProvider {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Provides the path to the plugin install location within the `Application Support` directory on the host machine.
    func applicationSupport() -> URL {
        fileManager
            .applicationSupportDirectory
            .appending(components: "Echo", "Plugins")
    }
}

private extension FileManager {

    var applicationSupportDirectory: URL {
        guard let directory = urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Failed to locate application support directory.")
        }
        return directory
    }
}
