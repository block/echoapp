import Foundation

// MARK: - TerminalUI

enum TerminalUI {

    /// Whether stdin is a TTY (interactive terminal).
    static var isInteractive: Bool {
        isatty(STDIN_FILENO) != 0
    }

    // MARK: - Raw Mode

    private static var originalTermios: termios?

    // Darwin-specific tuple indices for termios.c_cc
    private static let vminIndex = 16
    private static let vtimeIndex = 17

    /// Enable raw terminal mode (no echo, no line buffering, character-at-a-time input).
    static func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let buf = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            buf[vminIndex] = 1
            buf[vtimeIndex] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    /// Restore the original terminal settings.
    static func restoreTerminal() {
        guard var original = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        originalTermios = nil
    }

    // MARK: - Key Reading

    enum Key {
        case up
        case down
        case enter
        case character(Character)
        case escape
        case unknown
    }

    /// Read a single keypress (blocking). Handles arrow key escape sequences.
    static func readKey() -> Key {
        var buf = [UInt8](repeating: 0, count: 3)
        let n = read(STDIN_FILENO, &buf, 3)
        guard n > 0 else { return .unknown }

        var bytes = Array(buf.prefix(n))
        if bytes == [0x1B] {
            bytes += readAdditionalBytes(maxCount: 2, timeout: 0.025)
        }
        return key(from: bytes) ?? .unknown
    }

    fileprivate static func key(from bytes: [UInt8]) -> Key? {
        guard let first = bytes.first else { return nil }

        if bytes.count == 1 {
            switch first {
            case 0x0A, 0x0D: return .enter
            case 0x1B: return .escape
            case 0x03: return .character("\u{03}") // Ctrl+C
            default:
                let scalar = Unicode.Scalar(first)
                return .character(Character(scalar))
            }
        }

        if bytes.count >= 3 && bytes[0] == 0x1B && bytes[1] == 0x5B {
            switch bytes[2] {
            case 0x41: return .up    // ESC [ A
            case 0x42: return .down  // ESC [ B
            default: return .unknown
            }
        }

        return .unknown
    }

    fileprivate static func readAdditionalBytes(maxCount: Int, timeout: TimeInterval) -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        var bytes: [UInt8] = []

        while bytes.count < maxCount && Date() < deadline {
            var byte: UInt8 = 0
            let n = read(STDIN_FILENO, &byte, 1)
            if n == 1 {
                bytes.append(byte)
            } else {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }

        return bytes
    }

    // MARK: - ANSI Helpers

    /// Clear the current line and move cursor to beginning.
    static func clearLine() {
        write(STDERR_FILENO, "\r\u{1B}[K", 4)
    }

    /// Move cursor up N lines.
    static func cursorUp(_ n: Int) {
        guard n > 0 else { return }
        let seq = "\u{1B}[\(n)A"
        write(STDERR_FILENO, seq, seq.utf8.count)
    }

    /// Move cursor to the beginning of the current line.
    static func cursorToColumn0() {
        write(STDERR_FILENO, "\r", 1)
    }

    /// Hide the cursor.
    static func hideCursor() {
        let seq = "\u{1B}[?25l"
        write(STDERR_FILENO, seq, seq.utf8.count)
    }

    /// Show the cursor.
    static func showCursor() {
        let seq = "\u{1B}[?25h"
        write(STDERR_FILENO, seq, seq.utf8.count)
    }

    /// Clear the screen and move cursor to top-left.
    static func clearScreen() {
        let seq = "\u{1B}[2J\u{1B}[H"
        write(STDERR_FILENO, seq, seq.utf8.count)
    }

    /// Write a string to stderr (preserving stdout for machine-readable output).
    static func writeStderr(_ string: String) {
        FileHandle.standardError.write(string.data(using: .utf8)!)
    }

    // MARK: - Styled Text

    static func bold(_ text: String) -> String { "\u{1B}[1m\(text)\u{1B}[0m" }
    static func dim(_ text: String) -> String { "\u{1B}[2m\(text)\u{1B}[0m" }
    static func green(_ text: String) -> String { "\u{1B}[32m\(text)\u{1B}[0m" }
    static func cyan(_ text: String) -> String { "\u{1B}[36m\(text)\u{1B}[0m" }
    static func yellow(_ text: String) -> String { "\u{1B}[33m\(text)\u{1B}[0m" }
    static func red(_ text: String) -> String { "\u{1B}[31m\(text)\u{1B}[0m" }
    static func inverse(_ text: String) -> String { "\u{1B}[7m\(text)\u{1B}[0m" }
}

// MARK: - DevicePicker

struct DevicePicker {

    /// Show an interactive device picker that updates as devices are discovered.
    /// Returns the selected device, or nil if the user cancelled.
    static func pick(
        browser: DeviceBrowser,
        adbDevices: [DiscoveredDevice],
        timeout: TimeInterval = 10
    ) -> DiscoveredDevice? {
        TerminalUI.enableRawMode()
        TerminalUI.hideCursor()
        defer {
            TerminalUI.showCursor()
            TerminalUI.restoreTerminal()
        }

        var selectedIndex = 0
        var devices: [DiscoveredDevice] = adbDevices
        var lastRenderedLineCount = 0
        let startTime = Date()
        var scanComplete = false

        func render() {
            // Erase previous render
            if lastRenderedLineCount > 0 {
                TerminalUI.cursorUp(lastRenderedLineCount)
            }

            var lines: [String] = []

            if !scanComplete {
                let elapsed = Date().timeIntervalSince(startTime)
                let dots = String(repeating: ".", count: Int(elapsed) % 4)
                lines.append(TerminalUI.dim("  Searching for devices\(dots)"))
            } else {
                lines.append(TerminalUI.dim("  Scan complete."))
            }
            lines.append("")

            if devices.isEmpty {
                lines.append("  No devices found yet.")
            } else {
                for (i, device) in devices.enumerated() {
                    let displayName = device.displayName ?? device.name
                    let typeLabel = device.isAndroid ? "android" : "ios"
                    let tag = TerminalUI.dim("[\(typeLabel)]")
                    let number = "\(i + 1)."
                    if i == selectedIndex {
                        lines.append("  \(TerminalUI.cyan("->")) \(TerminalUI.bold(number)) \(TerminalUI.bold(displayName)) \(tag)")
                    } else {
                        lines.append("     \(TerminalUI.dim(number)) \(displayName) \(tag)")
                    }
                }
            }

            lines.append("")
            lines.append(TerminalUI.dim("  Use \u{2191}\u{2193} or j/k to navigate. Enter or number to select. q to quit."))

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
                // Move cursor back up past the cleared lines
                TerminalUI.cursorUp(lastRenderedLineCount - lines.count)
            }
            lastRenderedLineCount = lines.count
        }

        // Initial render
        TerminalUI.writeStderr("\n")
        render()

        // Use non-blocking reads with a poll loop so we can update the device list
        let originalFlags = fcntl(STDIN_FILENO, F_GETFL)
        _ = fcntl(STDIN_FILENO, F_SETFL, originalFlags | O_NONBLOCK)
        defer { _ = fcntl(STDIN_FILENO, F_SETFL, originalFlags) }

        while true {
            // Update device list from browser
            let bonjourDevices = browser.discoveredDevices
            let combined = bonjourDevices + adbDevices
            let changed = combined.map(\.name) != devices.map(\.name)
            devices = combined

            if !scanComplete && Date().timeIntervalSince(startTime) >= timeout {
                scanComplete = true
            }

            if selectedIndex >= devices.count && !devices.isEmpty {
                selectedIndex = devices.count - 1
            }

            if changed || !scanComplete {
                render()
            }

            // Try to read a key
            let key = tryReadKey()
            switch key {
            case .up:
                if !devices.isEmpty {
                    selectedIndex = max(0, selectedIndex - 1)
                    render()
                }
            case .down:
                if !devices.isEmpty {
                    selectedIndex = min(devices.count - 1, selectedIndex + 1)
                    render()
                }
            case .enter:
                if !devices.isEmpty {
                    TerminalUI.writeStderr("\n")
                    return devices[selectedIndex]
                }
            case .character(let ch):
                if ch == "q" || ch == "\u{03}" {
                    TerminalUI.writeStderr("\n")
                    return nil
                }
                if ch == "j" && !devices.isEmpty {
                    selectedIndex = min(devices.count - 1, selectedIndex + 1)
                    render()
                } else if ch == "k" && !devices.isEmpty {
                    selectedIndex = max(0, selectedIndex - 1)
                    render()
                } else if let digit = ch.wholeNumberValue, digit >= 1, digit <= devices.count {
                    selectedIndex = digit - 1
                    TerminalUI.writeStderr("\n")
                    return devices[selectedIndex]
                }
            case .escape:
                TerminalUI.writeStderr("\n")
                return nil
            case nil:
                break
            case .unknown:
                break
            }

            // If scan is complete and no devices, give up after a brief pause
            if scanComplete && devices.isEmpty {
                render()
                Thread.sleep(forTimeInterval: 0.5)
                TerminalUI.writeStderr("\n")
                return nil
            }

            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Non-blocking key read. Returns nil if no key is available.
    private static func tryReadKey() -> TerminalUI.Key? {
        var buf = [UInt8](repeating: 0, count: 3)
        let n = read(STDIN_FILENO, &buf, 3)
        guard n > 0 else { return nil }

        var bytes = Array(buf.prefix(n))
        if bytes == [0x1B] {
            bytes += TerminalUI.readAdditionalBytes(maxCount: 2, timeout: 0.025)
        }

        return TerminalUI.key(from: bytes)
    }
}
