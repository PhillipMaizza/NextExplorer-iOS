import Foundation

/// Reads and writes the ISO 8601 timestamps the server sends, with or without fractional seconds. The
/// formatters are built once because rows ask for a date on every render.
public enum ServerTimestamp {
    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func date(from text: String) -> Date? {
        withFraction.date(from: text) ?? plain.date(from: text)
    }

    /// `date` written as the server writes it, with fractional seconds.
    public static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// `date` in whole seconds, for the fields the server reads without a fraction.
    public static func wholeSecondString(from date: Date) -> String {
        plain.string(from: date)
    }
}
