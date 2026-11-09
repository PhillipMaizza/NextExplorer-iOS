@testable import FilesFeature
import Foundation
import Testing

struct DateDisplayFormatTests {
    /// Noon UTC, not midnight: keeps the calendar day stable across any reasonable local
    /// time zone the test machine might run in.
    private let date = Date(timeIntervalSince1970: 1_735_819_200) // 2025-01-02T12:00:00Z

    @Test
    func slashMonthDayYearFormatsAsSlashSeparatedUSOrder() {
        #expect(DateDisplayFormat.slashMonthDayYear.string(from: date) == "01/02/2025")
    }

    @Test
    func slashDayMonthYearFormatsAsSlashSeparatedInternationalOrder() {
        #expect(DateDisplayFormat.slashDayMonthYear.string(from: date) == "02/01/2025")
    }

    @Test
    func dashYearMonthDayFormatsAsISO8601DateOnly() {
        #expect(DateDisplayFormat.dashYearMonthDay.string(from: date) == "2025-01-02")
    }

    @Test
    func dashDayMonthYearFormatsAsDashSeparatedInternationalOrder() {
        #expect(DateDisplayFormat.dashDayMonthYear.string(from: date) == "02-01-2025")
    }

    @Test
    func dashMonthDayYearFormatsAsDashSeparatedUSOrder() {
        #expect(DateDisplayFormat.dashMonthDayYear.string(from: date) == "01-02-2025")
    }

    @Test
    func dotDayMonthYearFormatsAsDotSeparatedInternationalOrder() {
        #expect(DateDisplayFormat.dotDayMonthYear.string(from: date) == "02.01.2025")
    }

    @Test
    func abbreviatedMonthDayYearFormatsWithAShortMonthName() {
        #expect(DateDisplayFormat.abbreviatedMonthDayYear.string(from: date) == "Jan 2, 2025")
    }

    @Test
    func dayAbbreviatedMonthYearFormatsWithTheDayFirst() {
        #expect(DateDisplayFormat.dayAbbreviatedMonthYear.string(from: date) == "2 Jan 2025")
    }

    @Test
    func allCasesProduceADistinctNonEmptyStringForADayAndMonthThatDiffer() {
        // Uses the fixed `date` (day 2, month 1), not the live `.example`: on any day where
        // day-of-month == month number, the day/month-order pairs (dd/MM vs. MM/dd,
        // dd-MM vs. MM-dd) legitimately render identically, which would make an
        // `.example`-based uniqueness check flaky depending on which day it runs.
        let strings = DateDisplayFormat.allCases.filter { $0 != .system }.map { $0.string(from: date) }
        #expect(Set(strings).count == strings.count)
        #expect(strings.allSatisfy { !$0.isEmpty })
    }

    @Test
    func includeTimeAppendsATimeSuffixAfterTheDate() {
        let dateOnly = DateDisplayFormat.dashYearMonthDay.string(from: date)
        let withTime = DateDisplayFormat.dashYearMonthDay.string(from: date, includeTime: true)
        #expect(withTime.hasPrefix(dateOnly))
        #expect(withTime != dateOnly)
    }
}
