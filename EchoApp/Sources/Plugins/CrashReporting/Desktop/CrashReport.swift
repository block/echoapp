import Foundation

struct CrashReport: Codable, Identifiable {
    let timestamp: Int64
    let exceptionClass: String
    let message: String?
    let stackTrace: String
    let threadName: String
    let threadId: Int64
    let causeChain: [CauseInfo]?

    /// A stable composite identity. The Android client persists crashes to disk and re-sends them
    /// on every reconnect, and two crashes can share a millisecond timestamp (multi-threaded crashes,
    /// rapid repro loops), so `timestamp` alone is not unique. Combining it with the thread and
    /// exception class avoids duplicate `List` ids (and the resulting SwiftUI diagnostics) and gives
    /// the view model a key to dedupe on.
    var id: String { "\(timestamp)-\(threadId)-\(exceptionClass)" }

    var formattedTimestamp: String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var title: String {
        if let message {
            return "\(exceptionClass): \(message)"
        }
        return exceptionClass
    }
}

struct CauseInfo: Codable {
    let exceptionClass: String
    let message: String?
    /// Optional: the Android client drops per-cause frames because the full "Caused by:" chain is
    /// already inlined in the top-level `CrashReport.stackTrace` (via `Throwable.stackTraceToString()`).
    /// Decoding it as optional keeps the report decodable across client versions — a missing key here
    /// must not fail the whole `CrashReport` decode, since `PluginConnection.receive` silently drops
    /// (and tears down) any message that fails to decode.
    let stackTrace: String?

    var title: String {
        if let message {
            return "\(exceptionClass): \(message)"
        }
        return exceptionClass
    }
}
