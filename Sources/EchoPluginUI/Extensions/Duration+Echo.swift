import Foundation

public enum DurationFormatter {
    public static func string(from nanosecondString: String) -> String {
        if let nanoseconds = Double(nanosecondString) {
            return string(from: nanoseconds / 1000000)
        } else {
            return "--"
        }
    }

    public static func string(from timeInterval: TimeInterval) -> String {
        string(from: timeInterval, isPrecise: true)
    }

    public static func string(
        from timeInterval: TimeInterval,
        isPrecise: Bool
    ) -> String {
        // Nanoseconds
        if timeInterval < 0.000_000_95 {
            let nanoseconds = timeInterval * 1_000_000_000
            return isPrecise ?
            String(format: "%.1f ns", nanoseconds) :
            String(format: "%.0f ns", nanoseconds)
        }
        // Microseconds
        else if timeInterval < 0.000_95 {
            let microseconds = timeInterval * 1_000_000
            return isPrecise ?
            String(format: "%.1f \u{03BC}s", microseconds) :
            String(format: "%.0f \u{03BC}s", microseconds)
        }
        // Milliseconds
        else if timeInterval < 0.95 {
            let milliseconds = timeInterval * 1000
            return isPrecise ?
            String(format: "%.1f ms", milliseconds) :
            String(format: "%.0f ms", milliseconds)
        }
        // Seconds
        else if timeInterval < 200 {
            return String(format: "%.\(isPrecise ? "3" : "1")f s", timeInterval)
        }
        // Minutes
        else {
            let minutes = timeInterval / 60
            if minutes < 60 {
                return String(format: "%.1f min", minutes)
            }
            // Hours
            else {
                let hours = minutes / 60
                if hours < 24 {
                    return String(format: "%.1f h", hours)
                }
                // Days
                else {
                    let days = hours / 24
                    return String(format: "%.1f d", days)
                }
            }
        }
    }
}
