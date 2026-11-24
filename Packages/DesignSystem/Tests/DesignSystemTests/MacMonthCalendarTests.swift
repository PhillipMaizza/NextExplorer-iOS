#if os(macOS)
    @testable import DesignSystem
    import Foundation
    import Testing
    import TestUtils

    @Suite("Mac month calendar")
    struct MacMonthCalendarTests {
        private let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }()

        private func day(_ offset: Int) throws -> Date {
            try #require(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: MockDate.date)))
        }

        @Test("a later day keeps the time of day already chosen")
        func laterDayKeepsTheTime() throws {
            let time = try #require(calendar.date(byAdding: .day, value: 3, to: MockDate.date))
            let picked = try MacMonthCalendar.date(
                picking: day(10),
                keepingTimeOf: time,
                minimum: MockDate.date,
                calendar: calendar
            )

            #expect(try calendar.isDate(picked, inSameDayAs: day(10)))
            #expect(calendar.dateComponents([.hour, .minute], from: picked) == calendar.dateComponents(
                [.hour, .minute],
                from: time
            ))
        }

        @Test("today with a time already gone moves to the next full hour, never into the past")
        func todayWithAPastTimeMovesToTheNextHour() throws {
            let earlier = MockDate.date.addingTimeInterval(-60)
            let picked = try MacMonthCalendar.date(
                picking: day(0),
                keepingTimeOf: earlier,
                minimum: MockDate.date,
                calendar: calendar
            )

            #expect(picked > MockDate.date)
            #expect(calendar.component(.minute, from: picked) == .zero)
            #expect(picked.timeIntervalSince(MockDate.date) <= 3600)
        }
    }
#endif
