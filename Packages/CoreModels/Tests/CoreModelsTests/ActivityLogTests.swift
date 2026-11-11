@testable import CoreModels
import Foundation
import Testing

struct ActivityLogTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test
    func aPageDecodesItsEventsCursorAndKinds() throws {
        let page = try decode(ActivityPage.self, """
        {
            "events": [
                { "id": "e1", "at": "2026-11-11T07:14:33.812Z", "action": "sign-in", "outcome": "ok",
                  "userId": "u1", "actor": "phillip", "target": null, "detail": null, "ip": "10.0.0.2" },
                { "id": "e2", "at": "2026-11-11T07:10:00.000Z", "action": "file.delete", "outcome": "refused",
                  "actor": "guest", "target": "Docs/a.txt", "detail": "forbidden", "ip": "" }
            ],
            "nextBefore": "2026-11-11T07:10:00.000Z",
            "enabled": true,
            "actions": ["sign-in", "file.delete"]
        }
        """)

        #expect(page.events.count == 2)
        #expect(page.events[0].actor == "phillip")
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
        let page = try decode(ActivityPage.self, #"{ "events": [], "nextBefore": null, "enabled": false, "actions": [] }"#)

        #expect(page.events.isEmpty)
        #expect(page.nextBefore == nil)
        #expect(!page.isEnabled)
    }

    @Test
    func aNumericEventIDIsKeptAsText() throws {
        let event = try decode(ActivityEvent.self, #"{ "id": 42, "at": "2026-11-11T07:14:33Z", "action": "sign-out" }"#)

        #expect(event.id == "42")
        #expect(event.outcome == .ok)
    }

    @Test
    func anUnknownOutcomeIsTreatedAsOk() throws {
        let event = try decode(ActivityEvent.self, #"{ "id": "1", "at": "2026-11-11T07:14:33Z", "action": "x", "outcome": "weird" }"#)

        #expect(event.outcome == .ok)
    }

    @Test(arguments: ["2026-11-11T07:14:33.812Z", "2026-11-11T07:14:33Z"])
    func theTimestampParsesWithAndWithoutFractionalSeconds(at: String) throws {
        let event = try decode(ActivityEvent.self, #"{ "id": "1", "at": "\#(at)", "action": "x" }"#)

        #expect(event.date != nil)
    }

    @Test
    func anUnparseableTimestampHasNoDateButStaysUsableAsACursor() throws {
        let event = try decode(ActivityEvent.self, #"{ "id": "1", "at": "yesterday", "action": "x" }"#)

        #expect(event.date == nil)
        #expect(event.at == "yesterday")
    }

    @Test
    func settingsDefaultToOffAndNinetyDays() throws {
        let settings = try decode(ActivitySettings.self, "{}")

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
        let settings = try decode(SystemSettings.self, #"{ "activity": { "enabled": true, "retentionDays": 14 } }"#)

        #expect(settings.activity == ActivitySettings(isEnabled: true, retentionDays: 14))
        #expect(try decode(SystemSettings.self, "{}").activity == nil)
    }
}
