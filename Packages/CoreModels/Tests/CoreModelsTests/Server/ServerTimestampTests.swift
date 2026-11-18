@testable import CoreModels
import Foundation
import Testing

struct ServerTimestampTests {
    @Test
    func readsATimestampWithFractionalSeconds() throws {
        let date = try #require(ServerTimestamp.date(from: "2026-11-11T07:00:00.250Z"))

        #expect(date.timeIntervalSince1970 == 1_794_380_400.25)
    }

    @Test
    func readsATimestampWithoutFractionalSeconds() throws {
        let date = try #require(ServerTimestamp.date(from: "2026-11-11T07:00:00Z"))

        #expect(date.timeIntervalSince1970 == 1_794_380_400)
    }

    @Test(arguments: ["", "yesterday", "2026-11-11"])
    func anythingElseIsNil(text: String) {
        #expect(ServerTimestamp.date(from: text) == nil)
    }
}
