import Foundation

/// Reads the ISO 8601 timestamps the server sends, with or without fractional seconds. The
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
}
