import Foundation

public enum EchoTimestamp {
    private static let formatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm:ss.SSS"

        return dateFormatter
    }()

    public static func format(date: Date) -> String {
        formatter.string(from: date)
    }
}

public enum DateFormatters {
    public static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        // swiftlint:disable:next non_localized_date_formatter
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
