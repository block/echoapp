import Foundation

/**
 The macOS firewall prevents the iOS simulator from receiving incoming connections by default.
 This extension provides functions to check the state of the firewall and toggle exceptions for iOS development
 */
extension FirewallDaemon {

    public func iOSFirewallExceptionsEnabled() throws -> Bool {
        let xcodeSelect = XcodeSelect()
        let xcodeBinary = try xcodeSelect.pathToXcodeBinary()

        let firewallEntries = try firewallEntries()
        let xcodeEntry = firewallEntries.first { $0.path == xcodeBinary.path }

        return xcodeEntry?.allowed == true
    }

    public func toggleIOSFirewallExceptions() throws {
        let xcodeSelect = XcodeSelect()
        let xcodeBinary = try xcodeSelect.pathToXcodeBinary()

        if try iOSFirewallExceptionsEnabled() {
            try removeAllowedApplication(applicationPath: xcodeBinary.path)
        } else {
            try addAllowedApplication(applicationPath: xcodeBinary.path)
        }
    }

}
