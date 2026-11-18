@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct ActivityLogTests {
    @Test
    func aPageDecodesItsEventsCursorAndKinds() throws {
        let page = try CoreModelsFixture.activityLogPageWithEvents.decode(ActivityPage.self)

        #expect(page.events.count == 2)
        #expect(page.events[0].actor == TestAccount.username)
        #expect(page.events[0].target == nil)
        #expect(page.events[0].ip == "10.0.0.2")
        #expect(page.events[1].outcome == .refused)
        #expect(page.events[1].ip == nil)
        #expect(page.nextBefore == "2026-11-11T07:10:00.000Z")
        #expect(page.isEnabled)
        #expect(page.actions == ["sign-in", "file.delete"])
    }

    @Test
    func anEmptyPageHasNoCursorAndTheLogOff() throws {
        let page = try CoreModelsFixture.activityLogEmptyPage.decode(ActivityPage.self)

        #expect(page.events.isEmpty)
        #expect(page.nextBefore == nil)
        #expect(!page.isEnabled)
    }

    @Test
    func aNumericEventIDIsKeptAsText() throws {
        let event = try CoreModelsFixture.activityLogNumericEventId.decode(ActivityEvent.self)

        #expect(event.id == "42")
        #expect(event.outcome == .ok)
    }

    @Test
    func anUnknownOutcomeIsTreatedAsOk() throws {
        let event = try CoreModelsFixture.activityLogUnknownOutcome.decode(ActivityEvent.self)

        #expect(event.outcome == .ok)
    }

    @Test(arguments: [
        CoreModelsFixture.activityLogTimestampWithFractionalSeconds,
        .activityLogTimestampWithoutFractionalSeconds,
    ])
    func theTimestampParsesWithAndWithoutFractionalSeconds(fixture: CoreModelsFixture) throws {
        let event = try fixture.decode(ActivityEvent.self)

        #expect(event.date != nil)
    }

    @Test
    func anUnparseableTimestampHasNoDateButStaysUsableAsACursor() throws {
        let event = try CoreModelsFixture.activityLogUnparseableTimestamp.decode(ActivityEvent.self)

        #expect(event.date == nil)
        #expect(event.at == "yesterday")
    }

    @Test
    func settingsDefaultToOffAndNinetyDays() throws {
        let settings = try CoreModelsFixture.emptyObject.decode(ActivitySettings.self)

        #expect(!settings.isEnabled)
        #expect(settings.retentionDays == 90)
    }

    @Test
    func settingsEncodeBothFields() throws {
        let data = try JSONEncoder().encode(ActivitySettings(isEnabled: true, retentionDays: 30))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["enabled"] as? Bool == true)
        #expect(json["retentionDays"] as? Int == 30)
    }

    @Test
    func systemSettingsCarryTheActivitySection() throws {
        let settings = try CoreModelsFixture.activityLogSystemSettingsWithActivity.decode(SystemSettings.self)

        #expect(settings.activity == ActivitySettings(isEnabled: true, retentionDays: 14))
        #expect(try CoreModelsFixture.emptyObject.decode(SystemSettings.self).activity == nil)
    }
}
