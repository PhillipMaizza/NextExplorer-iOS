@testable import FilesFeature
import Foundation
import Testing

struct APITokenDatesTests {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    private let english = Locale(identifier: "en_US")

    @Test
    func aServerTimestampWithFractionalSecondsIsFormatted() {
        #expect(APITokenDates.display("2026-11-10T07:00:00.000Z", locale: english, timeZone: utc) == "Nov 10, 2026")
    }

    @Test
    func aTimestampWithoutFractionalSecondsIsFormatted() {
        #expect(APITokenDates.display("2026-11-10T07:00:00Z", locale: english, timeZone: utc) == "Nov 10, 2026")
    }

    @Test
    func theDayFollowsTheTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        #expect(APITokenDates.display("2026-11-10T20:00:00.000Z", locale: english, timeZone: tokyo) == "Nov 11, 2026")
    }

    @Test
    func somethingThatIsNotADateIsLeftOut() {
        #expect(APITokenDates.display("", locale: english, timeZone: utc) == nil)
        #expect(APITokenDates.display("yesterday", locale: english, timeZone: utc) == nil)
    }

    @Test
    func aTokenIsExpiredFromTheMomentItsExpiryPasses() {
        let expiry = "2026-11-10T07:00:00.000Z"
        let at = ISO8601DateFormatter().date(from: "2026-11-10T07:00:00Z") ?? .distantPast
        #expect(!APITokenDates.isExpired(expiry, now: at.addingTimeInterval(-1)))
        #expect(APITokenDates.isExpired(expiry, now: at))
        #expect(APITokenDates.isExpired(expiry, now: at.addingTimeInterval(1)))
    }

    @Test
    func aTokenThatNeverExpiresOrHasAnUnreadableExpiryIsNotExpired() {
        #expect(!APITokenDates.isExpired(nil, now: .distantFuture))
        #expect(!APITokenDates.isExpired("soon", now: .distantFuture))
    }
}
