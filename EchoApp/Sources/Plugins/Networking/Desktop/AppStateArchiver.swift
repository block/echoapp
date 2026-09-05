import Foundation

public protocol AppStateArchiver {
    func archiveAppState(_ state: AppState)
    func unarchiveAppState() -> AppState?
}

// MARK: -

public struct AppStateDiskArchiver: AppStateArchiver {

    public init() {}

    public func archiveAppState(_ state: AppState) {
        let encoder = JSONEncoder()

        do {
            try makeDirectoryIfNeeded(networkingPluginDataDirectory)
            try encoder.encode(state).write(to: archiveURL)
        } catch {
            fatalError("Failed to archive app state: \(error)")
        }
    }

    public func unarchiveAppState() -> AppState? {
        let decoder = JSONDecoder()

        do {
            let data = try Data(contentsOf: archiveURL)
            return try decoder.decode(AppState.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    private var archiveURL: URL {
        networkingPluginDataDirectory.appendingPathComponent("state.json")
    }

    private var networkingPluginDataDirectory: URL {
        let appSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupportDirectory.appendingPathComponent("Echo/PluginData/Networking")
    }

    private func makeDirectoryIfNeeded(_ directory: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
