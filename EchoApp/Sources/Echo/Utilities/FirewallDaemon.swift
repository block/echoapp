import Foundation

/// A Swift interface for the macOS firewall daemon, `socketfilterfw`
public protocol FirewallDaemon {
    func firewallEntries() throws -> [FirewallEntry]
    func addAllowedApplication(applicationPath: String) throws
    func removeAllowedApplication(applicationPath: String) throws
}

// MARK: -

public final class RealFirewallDaemon: FirewallDaemon {

    private let socketfilterfw = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    // MARK: - Life Cycle

    public init() {}

    // MARK: - FirewallDaemon

    public func firewallEntries() throws -> [FirewallEntry] {
        let listAppsOutput = try runCommands(["\(socketfilterfw) --listapps"])
        return FirewallEntriesDecoder.decode(from: listAppsOutput)
    }

    /*
     To reliably add an app to the firewall such that `--listapps` reports the correct status:
     1. Disable the firewall
     2. Add the app
     3. Re-enable the firewall
     */
    public func addAllowedApplication(applicationPath: String) throws {
        try runCommands(
            [
                "\(socketfilterfw) --setglobalstate off",
                "\(socketfilterfw) --add \"\(applicationPath)\"",
                "\(socketfilterfw) --setglobalstate on",
            ],
            sudo: true
        )
    }

    /*
     To reliably remove an app from the firewall such that `--listapps` reports the correct status:
     1. Remove the app
     2. Restart the firewall daemon
     I'm not sure why this process differs from adding an app. socketfilterfw is finicky.
     */
    public func removeAllowedApplication(applicationPath: String) throws {
        try runCommands(
            [
                "\(socketfilterfw) --remove \"\(applicationPath)\"",
                "\(socketfilterfw) -k",
            ],
            sudo: true
        )
    }

    // MARK: - Private Methods

    @discardableResult
    private func runCommands(_ commands: [String], sudo: Bool = false) throws -> String {
        let concatenatedCommands = commands
            .map {
                // Escape any inner quotes since we're sending this to Apple Script
                var command = $0.replacingOccurrences(of: "\"", with: "\\\"")

                if sudo {
                    command = "sudo \(command)"
                }
                return command
            }
            .joined(separator: " && ")

        var script = "do shell script \"\(concatenatedCommands)\""
        if sudo {
            script.append(" with administrator privileges")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output ?? ""
    }
}

// MARK: -

/// Describes an entry from the output of `socketfilterfw --listapps`
public struct FirewallEntry: Equatable {
    public var path: String
    public var allowed: Bool

    public init(path: String, allowed: Bool) {
        self.path = path
        self.allowed = allowed
    }
}

// MARK: -

/**
 Decodes the output of `socketfilterfw --listapps`
 Example input:

 ```
 ALF: total number of apps = 299

 1 :  /System/Library/CoreServices/ControlCenter.app
       ( Allow incoming connections )

 2 :  /usr/libexec/sharingd
       ( Allow incoming connections ) 
 ```
 */
public enum FirewallEntriesDecoder {

    public static func decode(from text: String) -> [FirewallEntry] {
        var entries = [FirewallEntry]()

        let lines = text.components(separatedBy: .newlines)
        var currentPath: String? = nil

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check if line contains a path (identified by its prefix with a number and colon)
            // `2 :  /usr/libexec/sharingd`
            if let entryNumber = trimmedLine.firstIndex(where: { $0.isNumber }),
               let pathStartIndex = trimmedLine.index(entryNumber, offsetBy: 5, limitedBy: trimmedLine.endIndex) {

                // Extract the path
                currentPath = String(trimmedLine[pathStartIndex...]).trimmingCharacters(in: .whitespaces)

            // Check if the line following the path indicates the `allowed` status
            // `( Allow incoming connections )` or `( Block incoming connections )`
            } else if let path = currentPath, trimmedLine.hasPrefix("(") {
                let allowed = trimmedLine.contains("( Allow incoming connections )")
                let entry = FirewallEntry(path: path, allowed: allowed)
                entries.append(entry)

                // Reset currentPath to prepare for the next entry
                currentPath = nil
            }
        }
        return entries
    }
}
