import Foundation
import Localization

/// User-facing date formatting choice, persisted locally (`@AppStorage("dateDisplayFormat")`)
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
    /// picking one is to *not* follow the device's locale. A fresh `DateFormatter` per call
    /// rather than one cached instance per case (nine long-lived formatters is wasteful) —
    /// but also rather than one *shared* cached instance, which would race under concurrent
    /// callers (Swift Testing runs tests in parallel by default; two tests reconfiguring the
    /// same formatter at once produced garbled results). This is called at most once per
    /// visible row, not a hot loop, so the construction cost is a non-issue either way.
    public func string(from date: Date, includeTime: Bool = false) -> String {
        let formatter = DateFormatter()
        switch self {
        case .system:
            formatter.dateFormat = nil
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .slashMonthDayYear:
            formatter.dateFormat = "MM/dd/yyyy"
        case .slashDayMonthYear:
            formatter.dateFormat = "dd/MM/yyyy"
        case .dashYearMonthDay:
            formatter.dateFormat = "yyyy-MM-dd"
        case .dashDayMonthYear:
            formatter.dateFormat = "dd-MM-yyyy"
        case .dashMonthDayYear:
            formatter.dateFormat = "MM-dd-yyyy"
        case .dotDayMonthYear:
            formatter.dateFormat = "dd.MM.yyyy"
        case .abbreviatedMonthDayYear:
            formatter.dateFormat = "MMM d, yyyy"
        case .dayAbbreviatedMonthYear:
            formatter.dateFormat = "d MMM yyyy"
        }
        let dateText = formatter.string(from: date)
        guard includeTime else { return dateText }

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return "\(dateText), \(timeFormatter.string(from: date))"
    }
}
