@testable import FilesFeature
import Foundation
import Testing
import TestUtils

struct DateDisplayFormatTests {
    /// Noon UTC the day after `MockDate.date` (2023-11-15T12:00:00Z), not midnight: keeps the calendar day
    /// stable across any reasonable local time zone the test machine might run in.
    private let date = MockDate.date.addingTimeInterval(49_600)

    @Test
    func slashMonthDayYearFormatsAsSlashSeparatedUSOrder() {
        #expect(DateDisplayFormat.slashMonthDayYear.string(from: date) == "11/15/2023")
    }

    @Test
    func slashDayMonthYearFormatsAsSlashSeparatedInternationalOrder() {
        #expect(DateDisplayFormat.slashDayMonthYear.string(from: date) == "15/11/2023")
    }

    @Test
    func dashYearMonthDayFormatsAsISO8601DateOnly() {
        #expect(DateDisplayFormat.dashYearMonthDay.string(from: date) == "2023-11-15")
    }

    @Test
    func dashDayMonthYearFormatsAsDashSeparatedInternationalOrder() {
        #expect(DateDisplayFormat.dashDayMonthYear.string(from: date) == "15-11-2023")
    }

    @Test
    func dashMonthDayYearFormatsAsDashSeparatedUSOrder() {
        #expect(DateDisplayFormat.dashMonthDayYear.string(from: date) == "11-15-2023")
    }

    @Test
    func dotDayMonthYearFormatsAsDotSeparatedInternationalOrder() {
        #expect(DateDisplayFormat.dotDayMonthYear.string(from: date) == "15.11.2023")
    }

    @Test
    func abbreviatedMonthDayYearFormatsWithAShortMonthName() {
        #expect(DateDisplayFormat.abbreviatedMonthDayYear.string(from: date) == "Nov 15, 2023")
    }

    @Test
    func dayAbbreviatedMonthYearFormatsWithTheDayFirst() {
        #expect(DateDisplayFormat.dayAbbreviatedMonthYear.string(from: date) == "15 Nov 2023")
    }

    @Test
    func allCasesProduceADistinctNonEmptyStringForADayAndMonthThatDiffer() {
        // Uses the fixed `date` (day 15, month 11), not the live `.example`: on any day where
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
