import Foundation
import Testing
@testable import Keychain

@Suite("KeychainClient live implementation")
struct KeychainClientTests {
    private func makeClient() -> KeychainClient {
        .live(configuration: KeychainConfiguration(service: "app.nextplorer.tests.\(UUID().uuidString)"))
    }

    @Test("save then load round-trips the same data")
    func saveThenLoad() throws {
        let client = makeClient()
        let payload = Data("hello".utf8)
        try client.save("session", payload)
        let loaded = try client.load("session")
        #expect(loaded == payload)
    }

    @Test("load returns nil for a key that was never saved")
    func loadMissingKey() throws {
        let client = makeClient()
        let loaded = try client.load("missing")
        #expect(loaded == nil)
    }

    @Test("save twice for the same key overwrites rather than duplicating")
    func saveOverwrites() throws {
        let client = makeClient()
        try client.save("session", Data("first".utf8))
        try client.save("session", Data("second".utf8))
        let loaded = try client.load("session")
        #expect(loaded == Data("second".utf8))
    }

    @Test("delete removes a saved item")
    func deleteRemovesItem() throws {
        let client = makeClient()
        try client.save("session", Data("payload".utf8))
        try client.delete("session")
        let loaded = try client.load("session")
        #expect(loaded == nil)
    }

    @Test("delete on a missing key does not throw")
    func deleteMissingKeyIsNoop() throws {
        let client = makeClient()
        try client.delete("never-saved")
    }

    @Test("edge case: empty data round-trips")
    func emptyDataRoundTrips() throws {
        let client = makeClient()
        try client.save("session", Data())
        let loaded = try client.load("session")
        #expect(loaded == Data())
    }

    @Test("edge case: keys are scoped per service — the same account key in a different service does not collide")
    func keysAreScopedPerService() throws {
        let serviceA = KeychainConfiguration(service: "app.nextplorer.tests.\(UUID().uuidString)")
        let serviceB = KeychainConfiguration(service: "app.nextplorer.tests.\(UUID().uuidString)")
        let clientA = KeychainClient.live(configuration: serviceA)
        let clientB = KeychainClient.live(configuration: serviceB)

        try clientA.save("session", Data("a".utf8))
        let loadedFromB = try clientB.load("session")
        #expect(loadedFromB == nil)
    }
}
