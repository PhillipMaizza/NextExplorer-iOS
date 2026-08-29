import Foundation
import Localization

/// User-facing date formatting choice, persisted locally (`AppStorageKeys.dateDisplayFormat`)
/// rather than through `UserPreferences`/`GET|PATCH /api/settings` — purely a client display
/// preference the real server has no concept of, same as `browseViewMode`.
public enum DateDisplayFormat: String, CaseIterable, Identifiable, Sendable {
    case system
    case slashMonthDayYear
    case slashDayMonthYear
    case dashYearMonthDay
    case dashDayMonthYear
    case dashMonthDayYear
    case dotDayMonthYear
    case abbreviatedMonthDayYear
    case dayAbbreviatedMonthYear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: L10n.DateFormat.automatic
        case .slashMonthDayYear: "MM/DD/YYYY"
        case .slashDayMonthYear: "DD/MM/YYYY"
        case .dashYearMonthDay: "YYYY-MM-DD"
        case .dashDayMonthYear: "DD-MM-YYYY"
        case .dashMonthDayYear: "MM-DD-YYYY"
        case .dotDayMonthYear: "DD.MM.YYYY"
        case .abbreviatedMonthDayYear: "MMM D, YYYY"
        case .dayAbbreviatedMonthYear: "D MMM YYYY"
        }
    }

    /// Today, rendered in this format — shown as a subtitle in the picker so the user sees
    /// what the abbreviated pattern actually looks like before picking it.
    public func example(includeTime: Bool = false) -> String {
        string(from: Date(), includeTime: includeTime)
    }

    /// Every case but `.system` is a fixed literal pattern by design — the whole point of
    /// picking one is to *not* follow the device's locale. `string(from:)` runs once per
    /// visible row, so the formatters are built once and cached (behind a lock, since Swift
    /// Testing runs cases in parallel) rather than reallocated on every call.
    public func string(from date: Date, includeTime: Bool = false) -> String {
        let dateText = Self.cache.dateFormatter(for: self).string(from: date)
        guard includeTime else { return dateText }
        return "\(dateText), \(Self.cache.timeFormatter.string(from: date))"
    }

    private var dateFormatPattern: String? {
        switch self {
        case .system: nil
        case .slashMonthDayYear: "MM/dd/yyyy"
        case .slashDayMonthYear: "dd/MM/yyyy"
        case .dashYearMonthDay: "yyyy-MM-dd"
        case .dashDayMonthYear: "dd-MM-yyyy"
        case .dashMonthDayYear: "MM-dd-yyyy"
        case .dotDayMonthYear: "dd.MM.yyyy"
        case .abbreviatedMonthDayYear: "MMM d, yyyy"
        case .dayAbbreviatedMonthYear: "d MMM yyyy"
        }
    }

    private static let cache = FormatterCache()

    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [DateDisplayFormat: DateFormatter] = [:]

        let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }()

        func dateFormatter(for format: DateDisplayFormat) -> DateFormatter {
            lock.lock()
            defer { lock.unlock() }
            if let existing = formatters[format] { return existing }
            let formatter = DateFormatter()
            if let pattern = format.dateFormatPattern {
                formatter.dateFormat = pattern
            } else {
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
            }
            formatters[format] = formatter
            return formatter
        }
    }
}
