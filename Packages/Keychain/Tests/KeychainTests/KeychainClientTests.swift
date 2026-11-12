import Foundation
@testable import Keychain
import Testing
import TestUtils

@Suite("KeychainClient live implementation")
struct KeychainClientTests {
    private func makeClient() -> KeychainClient {
        .live(configuration: KeychainConfiguration(service: "app.nextplorer.tests.\(TestID.name())"))
    }

    @Test("save then load round-trips the same data")
    func saveThenLoad() throws {
        let client = makeClient()
        let payload = Data("hello".utf8)
        try client.save(TestStorageKey.session, payload)
        let loaded = try client.load(TestStorageKey.session)
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
        try client.save(TestStorageKey.session, Data("first".utf8))
        try client.save(TestStorageKey.session, Data("second".utf8))
        let loaded = try client.load(TestStorageKey.session)
        #expect(loaded == Data("second".utf8))
    }

    @Test("delete removes a saved item")
    func deleteRemovesItem() throws {
        let client = makeClient()
        try client.save(TestStorageKey.session, Data("payload".utf8))
        try client.delete(TestStorageKey.session)
        let loaded = try client.load(TestStorageKey.session)
        #expect(loaded == nil)
    }

    @Test("delete on a missing key does not throw")
    func deleteMissingKeyIsNoop() throws {
        let client = makeClient()
        try client.save(Constants.keptValue, Data("value".utf8))

        try client.delete(Constants.missingKey)

        #expect(try client.load(Constants.missingKey) == nil)
        #expect(try client.load(Constants.keptValue) == Data("value".utf8))
    }

    @Test("edge case: empty data round-trips")
    func emptyDataRoundTrips() throws {
        let client = makeClient()
        try client.save(TestStorageKey.session, Data())
        let loaded = try client.load(TestStorageKey.session)
        #expect(loaded == Data())
    }

    @Test("edge case: keys are scoped per service: the same account key in a different service does not collide")
    func keysAreScopedPerService() throws {
        let serviceA = KeychainConfiguration(service: "app.nextplorer.tests.\(TestID.name())")
        let serviceB = KeychainConfiguration(service: "app.nextplorer.tests.\(TestID.name())")
        let clientA = KeychainClient.live(configuration: serviceA)
        let clientB = KeychainClient.live(configuration: serviceB)

        try clientA.save(TestStorageKey.session, Data("a".utf8))
        let loadedFromB = try clientB.load(TestStorageKey.session)
        #expect(loadedFromB == nil)
    }
}

private enum Constants {
    static let keptValue = "kept"
    static let missingKey = "never-saved"
}
