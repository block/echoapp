import EchoConnection
import Foundation

// MARK: - SessionMonitorView

/// Renders a live dashboard of session activity to the terminal.
final class SessionMonitorView: @unchecked Sendable {
    private let lock = NSLock()
    private var deviceName: String
    private var deviceType: String
    private var sessionID: String
    private var sessionPath: String
    private var status: ConnectionStatus = .connecting
    private var totalPayloads = 0
    private var pluginStats: [String: PluginStat] = [:]
    private var startTime = Date()
    private var lastRenderedLineCount = 0
    private var timer: DispatchSourceTimer?

    struct PluginStat {
        var count: Int = 0
        var lastReceived: Date = Date()
    }

    enum ConnectionStatus: String {
        case connecting = "Connecting"
        case connected = "Connected"
        case disconnected = "Disconnected"
    }

    init(deviceName: String, deviceType: String, sessionID: String, sessionPath: String) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.sessionID = sessionID
        self.sessionPath = sessionPath
    }

    // MARK: - State Updates

    func recordPayload(pluginID: String) {
        lock.lock()
        totalPayloads += 1
        var stat = pluginStats[pluginID] ?? PluginStat()
        stat.count += 1
        stat.lastReceived = Date()
        pluginStats[pluginID] = stat
        lock.unlock()
    }

    func setStatus(_ newStatus: ConnectionStatus) {
        lock.lock()
        status = newStatus
        lock.unlock()
    }

    func resetStats() {
        lock.lock()
        totalPayloads = 0
        pluginStats.removeAll()
        lock.unlock()
    }

    // MARK: - Rendering

    func start() {
        TerminalUI.hideCursor()
        render()

        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "echoapp.monitor"))
        source.schedule(deadline: .now(), repeating: .milliseconds(500))
        source.setEventHandler { [weak self] in
            self?.render()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
        render()
        TerminalUI.showCursor()
        TerminalUI.writeStderr("\n")
    }

    private func render() {
        lock.lock()
        let currentStatus = status
        let currentTotal = totalPayloads
        let stats = pluginStats
        lock.unlock()

        let now = Date()
        let uptime = formatDuration(now.timeIntervalSince(startTime))

        // Move cursor back to overwrite previous render
        if lastRenderedLineCount > 0 {
            TerminalUI.cursorUp(lastRenderedLineCount)
        }

        var lines: [String] = []

        // Header box
        let statusIcon: String
        let statusText: String
        switch currentStatus {
        case .connecting:
            statusIcon = TerminalUI.yellow("●")
            statusText = TerminalUI.yellow("Connecting")
        case .connected:
            statusIcon = TerminalUI.green("●")
            statusText = TerminalUI.green("Connected")
        case .disconnected:
            statusIcon = TerminalUI.red("●")
            statusText = TerminalUI.red("Disconnected")
        }

        let typeLabel = TerminalUI.dim("[\(deviceType)]")

        lines.append("")
        lines.append("  \(TerminalUI.bold("EchoApp"))  \(statusIcon) \(statusText)")
        lines.append("")
        lines.append("  \(TerminalUI.dim("Device:"))   \(deviceName) \(typeLabel)")
        lines.append("  \(TerminalUI.dim("Session:"))  \(sessionID)")
        lines.append("  \(TerminalUI.dim("Data:"))     \(sessionPath)")
        lines.append("  \(TerminalUI.dim("Uptime:"))   \(uptime)     \(TerminalUI.dim("Payloads:")) \(currentTotal)")
        lines.append("")

        // Plugin table
        if !stats.isEmpty {
            let sortedPlugins = stats.sorted { $0.value.count > $1.value.count }

            let nameHeader = "Plugin"
            let countHeader = "Payloads"
            let lastHeader = "Last received"

            let maxNameLen = max(nameHeader.count, sortedPlugins.map(\.key.count).max() ?? 0)
            let countColWidth = max(countHeader.count, 8)

            lines.append("  \(TerminalUI.bold(pad(nameHeader, to: maxNameLen)))  \(TerminalUI.bold(padLeft(countHeader, to: countColWidth)))  \(TerminalUI.bold(lastHeader))")
            lines.append("  \(TerminalUI.dim(String(repeating: "-", count: maxNameLen)))  \(TerminalUI.dim(String(repeating: "-", count: countColWidth)))  \(TerminalUI.dim(String(repeating: "-", count: 14)))")

            for (plugin, stat) in sortedPlugins {
                let ago = formatAgo(now.timeIntervalSince(stat.lastReceived))
                lines.append("  \(pad(plugin, to: maxNameLen))  \(padLeft("\(stat.count)", to: countColWidth))  \(TerminalUI.dim(ago))")
            }
        } else {
            lines.append("  \(TerminalUI.dim("Waiting for data..."))")
        }

        lines.append("")
        lines.append("  \(TerminalUI.dim("Press Ctrl+C to disconnect  |  Data is written to JSONL files"))")

        for line in lines {
            TerminalUI.clearLine()
            TerminalUI.writeStderr(line + "\n")
        }
        // Clear any leftover rows from previous longer render
        if lines.count < lastRenderedLineCount {
            for _ in 0..<(lastRenderedLineCount - lines.count) {
                TerminalUI.clearLine()
                TerminalUI.writeStderr("\n")
            }
            TerminalUI.cursorUp(lastRenderedLineCount - lines.count)
        }
        lastRenderedLineCount = lines.count
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h)h \(m)m \(s)s"
        } else if m > 0 {
            return "\(m)m \(s)s"
        } else {
            return "\(s)s"
        }
    }

    private func formatAgo(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 1 { return "just now" }
        if total < 60 { return "\(total)s ago" }
        let m = total / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        return "\(h)h ago"
    }

    private func pad(_ string: String, to width: Int) -> String {
        string.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func padLeft(_ string: String, to width: Int) -> String {
        if string.count >= width { return string }
        return String(repeating: " ", count: width - string.count) + string
    }
}
