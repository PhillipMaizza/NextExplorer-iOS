@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("TrashEvent decoding")
struct TrashEventTests {
    @Test("an integer id decodes as a string")
    func integerIdDecodesAsString() throws {
        let event = try CoreModelsFixture.trashAdminEventIntegerId.decode(TrashEvent.self)
        #expect(event == TrashEvent(id: "17", kind: "purge-failed", itemName: "old.log", createdAt: nil))
    }

    @Test("a text id is kept as is together with the item name and timestamp text")
    func textIdIsKept() throws {
        let event = try CoreModelsFixture.trashAdminEventStringId.decode(TrashEvent.self)
        #expect(event == TrashEvent(id: "evt-9", kind: "purged", itemName: "a.txt", createdAt: "2023-11-14T22:13:20Z"))
    }
}
