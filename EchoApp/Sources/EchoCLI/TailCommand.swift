import ArgumentParser
import Foundation

struct TailCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tail",
        abstract: "Tail live plugin data from the current EchoApp session."
    )

    @Argument(help: "Plugin name to tail (e.g., networking, analytics, logging). Omit to tail all plugins.")
    var plugin: String?

    @Option(name: .long, help: "Session ID to tail. Defaults to the current active session.")
    var session: String?

    @Option(name: .shortAndLong, help: "Number of most recent lines to show before following.")
    var lines: Int = 10

    @Flag(name: .shortAndLong, help: "Follow the file for new data (like tail -f). Press Ctrl+C to stop.")
    var follow: Bool = false

    func validate() throws {
        guard lines >= 0 else {
            throw ValidationError("--lines must be non-negative.")
        }
    }

    func run() throws {
        let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: session)

        if let plugin {
            try tailPlugin(plugin, sessionURL: sessionURL)
        } else {
            try tailAllPlugins(sessionURL: sessionURL)
        }
    }

    private func tailPlugin(_ pluginName: String, sessionURL: URL) throws {
        let fileURL = sessionURL.appendingPathComponent("\(pluginName).jsonl")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EchoCLIError.pluginNotFound(pluginName)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let allLines = content.split(separator: "\n", omittingEmptySubsequences: true)
        let recentLines = allLines.suffix(lines)
        for line in recentLines {
            print(line)
        }

        if follow {
            tailFollow(fileURL: fileURL, startOffset: content.utf8.count)
        }
    }

    private func tailAllPlugins(sessionURL: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: sessionURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if files.isEmpty {
            print("No plugin data in session.")
            return
        }

        // Collect all lines with their source plugin, sort by timestamp
        var allEntries: [(plugin: String, line: String, timestamp: String)] = []
        for file in files {
            let plugin = file.deletingPathExtension().lastPathComponent
            let content = try String(contentsOf: file, encoding: .utf8)
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let ts = extractTimestamp(from: String(line)) ?? ""
                allEntries.append((plugin: plugin, line: String(line), timestamp: ts))
            }
        }

        allEntries.sort { $0.timestamp < $1.timestamp }
        let recentEntries = allEntries.suffix(lines)
        for entry in recentEntries {
            print(entry.line)
        }

        if follow {
            // In follow mode for all plugins, watch the session directory
            tailFollowDirectory(sessionURL: sessionURL, files: files)
        }
    }

    private func tailFollow(fileURL: URL, startOffset: Int) {
        guard let fh = FileHandle(forReadingAtPath: fileURL.path) else { return }
        fh.seek(toFileOffset: UInt64(startOffset))

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fh.fileDescriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler {
            let data = fh.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print(text, terminator: "")
            }
        }
        source.setCancelHandler { fh.closeFile() }

        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            source.cancel()
            sigintSource.cancel()
            Foundation.exit(0)
        }
        sigintSource.resume()
        source.resume()
        dispatchMain()
    }

    private func tailFollowDirectory(sessionURL: URL, files: [URL]) {
        var handles: [(url: URL, handle: FileHandle)] = []
        for file in files {
            guard let fh = FileHandle(forReadingAtPath: file.path) else { continue }
            fh.seekToEndOfFile()
            handles.append((url: file, handle: fh))
        }

        // Poll for new data
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            for h in handles { h.handle.closeFile() }
            sigintSource.cancel()
            Foundation.exit(0)
        }
        sigintSource.resume()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler {
            for h in handles {
                let data = h.handle.readDataToEndOfFile()
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    print(text, terminator: "")
                }
            }

            // Check for new files
            if let newFiles = try? FileManager.default.contentsOfDirectory(at: sessionURL, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension == "jsonl" })
                .filter({ url in !handles.contains(where: { $0.url == url }) }) {
                for file in newFiles {
                    if let fh = FileHandle(forReadingAtPath: file.path) {
                        let data = fh.readDataToEndOfFile()
                        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                            print(text, terminator: "")
                        }
                        handles.append((url: file, handle: fh))
                    }
                }
            }
        }
        timer.resume()
        dispatchMain()
    }

    private func extractTimestamp(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["timestamp"] as? String else {
            return nil
        }
        return ts
    }
}
