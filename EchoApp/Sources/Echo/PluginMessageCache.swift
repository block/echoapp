import Foundation
import Combine
import EchoConnection
import EchoPluginAPI

/// Caches plugin messages for the current session
actor PluginMessageCache {
    
    // MARK: - Shared Instance
    
    static let shared = PluginMessageCache()
    
    // MARK: - Types
    
    struct PluginData: Codable {
        let timestamp: Date
        let payload: PluginPayload

        enum CodingKeys: String, CodingKey {
            case timestamp
            case payload
        }
    }
    
    // MARK: - Properties
    
    private let fileManager: FileManager
    private let cacheURL: URL
    private let maxMessagesPerPlugin: Int

    // MARK: - Initialization
    
    init(fileManager: FileManager = .default, maxMessagesPerPlugin: Int = 1000) {
        self.fileManager = fileManager
        self.maxMessagesPerPlugin = maxMessagesPerPlugin
        self.cacheURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Echo/Cache", isDirectory: true)

        try? fileManager.createDirectory(at: self.cacheURL, withIntermediateDirectories: true)

        // Clean up legacy cache directory from previous versions
        Task.detached(priority: .utility) {
            let legacyCacheURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Echo/PluginCache", isDirectory: true)
            if fileManager.fileExists(atPath: legacyCacheURL.path) {
                try? fileManager.removeItem(at: legacyCacheURL)
            }
        }
    }
    
    deinit {
        if fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.removeItem(at: cacheURL)
        }
    }
    
    // MARK: - Cache Management
    
    /// Clears all cached data
    func clearCache() async {
        await Task.detached(priority: .utility) { [fileManager, cacheURL] in
            if fileManager.fileExists(atPath: cacheURL.path) {
                try? fileManager.removeItem(at: cacheURL)
            }
            // Recreate the directory
            try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }.value
    }
    
    /// Clear cache on app startup
    func clearCacheOnStartup() async {
        await rotateCacheForBackgroundDeletion()
    }

    private func rotateCacheForBackgroundDeletion() async {
        let fileManager = fileManager
        let cacheURL = cacheURL
        let cacheParentURL = cacheURL.deletingLastPathComponent()
        let deletionURL = cacheParentURL
            .appendingPathComponent("Cache-Deleting-\(UUID().uuidString)", isDirectory: true)

        if fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.moveItem(at: cacheURL, to: deletionURL)
        }

        try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        // Startup only needs the cache rotated; the old cache can be removed after launch continues.
        let deletionURLs = Self.cacheDeletionURLs(in: cacheParentURL, including: deletionURL, fileManager: fileManager)
        Task.detached(priority: .utility) { [fileManager, deletionURLs] in
            for deletionURL in deletionURLs where fileManager.fileExists(atPath: deletionURL.path) {
                try? fileManager.removeItem(at: deletionURL)
            }
        }
    }

    private nonisolated static func cacheDeletionURLs(
        in cacheParentURL: URL,
        including currentDeletionURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let abandonedDeletionURLs = (try? fileManager.contentsOfDirectory(
            at: cacheParentURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var deletionURLs = [currentDeletionURL]
        for deletionURL in abandonedDeletionURLs where deletionURL.lastPathComponent.hasPrefix("Cache-Deleting-") {
            if !deletionURLs.contains(deletionURL) {
                deletionURLs.append(deletionURL)
            }
        }
        return deletionURLs
    }
    
    /// Get the directory URL for a specific plugin
    private nonisolated func pluginDirectory(for pluginId: PluginIdentifier) -> URL {
        let safePluginId = pluginId.replacingOccurrences(of: ".", with: "-")
        return cacheURL.appendingPathComponent(safePluginId, isDirectory: true)
    }
    
    /// Purge oldest messages for a plugin if exceeding the max limit
    private func purgeOldMessagesIfNeeded(for pluginId: PluginIdentifier) async throws {
        try await Task.detached(priority: .utility) { [fileManager, maxMessagesPerPlugin] in
            let pluginDir = self.pluginDirectory(for: pluginId)
            
            guard fileManager.fileExists(atPath: pluginDir.path) else { return }
            
            let files = try fileManager.contentsOfDirectory(
                at: pluginDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // Sort by timestamp (oldest first)
            let sortedFiles = files.sorted { file1, file2 in
                // Extract timestamp from filename (format: {timestamp}-{uuid}.json)
                let timestamp1 = self.extractTimestamp(from: file1.lastPathComponent) ?? 0
                let timestamp2 = self.extractTimestamp(from: file2.lastPathComponent) ?? 0
                return timestamp1 < timestamp2
            }
            
            // Delete oldest files if we exceed the limit
            let filesToDelete = sortedFiles.count - maxMessagesPerPlugin
            if filesToDelete > 0 {
                for file in sortedFiles.prefix(filesToDelete) {
                    try? fileManager.removeItem(at: file)
                }
            }
        }.value
    }
    
    /// Extract timestamp from filename
    private nonisolated func extractTimestamp(from filename: String) -> TimeInterval? {
        let components = filename.components(separatedBy: "-")
        guard let timestampString = components.first,
              let timestamp = TimeInterval(timestampString) else {
            return nil
        }
        return timestamp
    }
    
    // MARK: - Public Methods
    
    /// Cache a plugin payload
    func cache(payload: Data, for pluginId: PluginIdentifier) async throws {
        let data = PluginData(
            timestamp: Date(),
            payload: .init(
                pluginID: pluginId,
                data: payload
            )
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        
        let pluginDir = pluginDirectory(for: pluginId)
        let timestamp = Int(data.timestamp.timeIntervalSince1970)
        let uniqueId = UUID().uuidString
        let filename = "\(timestamp)-\(uniqueId).json"
        let fileURL = pluginDir.appendingPathComponent(filename)
        
        try await Task.detached(priority: .utility) { [fileManager] in
            // Create plugin directory if it doesn't exist
            try fileManager.createDirectory(at: pluginDir, withIntermediateDirectories: true)
            try encoded.write(to: fileURL)
        }.value
        
        // Purge old messages if exceeding limit
        try? await purgeOldMessagesIfNeeded(for: pluginId)
    }
    
    /// Get all cached data for a plugin
    func getCachedData(for pluginId: PluginIdentifier) async throws -> [PluginData] {
        try await Task.detached(priority: .utility) { [fileManager] in
            let pluginDir = self.pluginDirectory(for: pluginId)
            
            guard fileManager.fileExists(atPath: pluginDir.path) else {
                return []
            }
            
            let files = try fileManager.contentsOfDirectory(at: pluginDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            let decoder = JSONDecoder()
            var loadedData: [PluginData] = []
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    let pluginData = try decoder.decode(PluginData.self, from: data)
                    loadedData.append(pluginData)
                } catch {
                    continue
                }
            }
            return loadedData.sorted { $0.timestamp < $1.timestamp }
        }.value
    }
    
    /// Export data for specified plugins to a bundle-like archive
    func exportData(for pluginIds: [PluginIdentifier], to archiveURL: URL) async throws {
        try await Task.detached(priority: .utility) { [fileManager] in
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            let archiveContents = tempDir.appendingPathComponent("\(Int(Date().timeIntervalSince1970)).echoarchive")
            try fileManager.createDirectory(at: archiveContents, withIntermediateDirectories: true)
            let contentsDir = archiveContents.appendingPathComponent("Contents")
            let dataDir = contentsDir.appendingPathComponent("Data")
            try fileManager.createDirectory(at: contentsDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
            
            for pluginId in pluginIds {
                let sourcePluginDir = self.pluginDirectory(for: pluginId)
                guard fileManager.fileExists(atPath: sourcePluginDir.path) else { continue }
                
                let safePluginId = pluginId.replacingOccurrences(of: ".", with: "-")
                let destPluginDir = dataDir.appendingPathComponent(safePluginId)
                try fileManager.createDirectory(at: destPluginDir, withIntermediateDirectories: true)
                
                let files = try fileManager.contentsOfDirectory(at: sourcePluginDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                for file in files {
                    let destination = destPluginDir.appendingPathComponent(file.lastPathComponent)
                    try fileManager.copyItem(at: file, to: destination)
                }
            }
            
            let infoPlist: [String: Any] = [
                "ExportDate": Date(),
                "ExportVersion": "1.0",
                "Plugins": pluginIds
            ]
            let infoPlistURL = contentsDir.appendingPathComponent("Info.plist")
            (infoPlist as NSDictionary).write(to: infoPlistURL, atomically: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", archiveContents.path, archiveURL.path]
            try process.run()
            process.waitUntilExit()
        }.value
    }
    
    /// Import data from an archive
    func importData(from archiveURL: URL) async throws -> [PluginData] {
        try await Task.detached(priority: .utility) { [fileManager] in
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, tempDir.path]
            try process.run()
            process.waitUntilExit()
            let archives = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "echoarchive" }
            guard let archiveContents = archives.first else {
                throw NSError(domain: "xyz.block.echoapp", code: -1, 
                            userInfo: [NSLocalizedDescriptionKey: "Invalid archive format"])
            }
            let contentsDir = archiveContents.appendingPathComponent("Contents")
            let dataDir = contentsDir.appendingPathComponent("Data")
            var allData: [PluginData] = []
            let decoder = JSONDecoder()
            let pluginDirs = try fileManager.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)
            for pluginDir in pluginDirs {
                let files = try fileManager.contentsOfDirectory(at: pluginDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                for file in files {
                    let data = try Data(contentsOf: file)
                    let pluginData = try decoder.decode(PluginData.self, from: data)
                    allData.append(pluginData)
                }
            }
            return allData.sorted { $0.timestamp < $1.timestamp }
        }.value
    }
    
    /// Import archive data directly into the cache directory structure
    func importArchiveIntoCache(from archiveURL: URL) async throws {
        try await Task.detached(priority: .utility) { [fileManager, cacheURL] in
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Extract the archive
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, tempDir.path]
            try process.run()
            process.waitUntilExit()
            
            // Find the archive contents
            let archives = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "echoarchive" }
            guard let archiveContents = archives.first else {
                throw NSError(domain: "xyz.block.echoapp", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid archive format"])
            }
            
            let contentsDir = archiveContents.appendingPathComponent("Contents")
            let dataDir = contentsDir.appendingPathComponent("Data")
            
            // Clear existing cache
            if fileManager.fileExists(atPath: cacheURL.path) {
                try? fileManager.removeItem(at: cacheURL)
            }
            try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            
            // Copy plugin directories from archive to cache
            let pluginDirs = try fileManager.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)
            for pluginDir in pluginDirs {
                let pluginName = pluginDir.lastPathComponent
                let destinationDir = cacheURL.appendingPathComponent(pluginName)
                try fileManager.copyItem(at: pluginDir, to: destinationDir)
            }
        }.value
    }
    
    /// Get a formatted filename for export
    static func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "echo_export_\(timestamp).echoarchive"
    }
    
    /// Cache a plugin message
    func addMessage(pluginId: String, payload: PluginPayload) async throws {
        let data = PluginData(
            timestamp: Date(),
            payload: payload
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        
        let pluginDir = pluginDirectory(for: pluginId)
        let timestamp = Int(data.timestamp.timeIntervalSince1970)
        let uniqueId = UUID().uuidString
        let filename = "\(timestamp)-\(uniqueId).json"
        let fileURL = pluginDir.appendingPathComponent(filename)
        
        try await Task.detached(priority: .utility) { [fileManager] in
            // Create plugin directory if it doesn't exist
            try fileManager.createDirectory(at: pluginDir, withIntermediateDirectories: true)
            try encoded.write(to: fileURL)
        }.value
        
        // Purge old messages if exceeding limit
        try? await purgeOldMessagesIfNeeded(for: pluginId)
    }
}
