import Foundation
@testable import Keychain
import Testing
import TestUtils

@Suite("KeychainClient waiting for the launch migration")
struct KeychainClientGateTests {
    enum Operation: CaseIterable, Sendable {
        case save, delete

        func run(_ client: KeychainClient) {
            switch self {
            case .save: try? client.save(TestStorageKey.session, Data())
            case .delete: try? client.delete(TestStorageKey.session)
            }
        }
    }

    @Test("a write or delete waits for the migration that began before it and runs after it finished", .timeLimit(.minutes(1)), arguments: Operation.allCases)
    func writeWaitsForMigration(_ operation: Operation) async {
        let gate = KeychainMigrationGate()
        let events = LockIsolated<[String]>([])
        let (callerStarted, signalCaller) = AsyncStream.makeStream(of: Void.self)
        let client = KeychainClient(
            save: { _, _ in events.withValue { $0.append(Constants.ran) } },
            load: { _ in nil },
            delete: { _ in events.withValue { $0.append(Constants.ran) } }
        ).waiting(for: gate)

        gate.begin()
        let caller = Task.detached {
            signalCaller.yield()
            operation.run(client)
        }
        for await _ in callerStarted {
            break
        }
        events.withValue { $0.append(Constants.migrated) }
        gate.finish()
        await caller.value

        #expect(events.value == [Constants.migrated, Constants.ran])
    }

    @Test("the wrapper hands back what the wrapped client returned and thrown")
    func wrapperPassesResultsAndErrorsThrough() throws {
        let payload = Data(TestStorageKey.session.utf8)
        let client = KeychainClient(
            save: { _, _ in throw KeychainError.unexpectedItemFormat },
            load: { _ in payload },
            delete: { _ in }
        ).waiting(for: KeychainMigrationGate())

        #expect(try client.load(TestStorageKey.session) == payload)
        #expect(throws: KeychainError.unexpectedItemFormat) {
            try client.save(TestStorageKey.session, payload)
        }
    }

    @Test("the legacy Mac migration moves nothing in a build without the keychain entitlement and keeps the item readable")
    func legacyMigrationWithoutEntitlementKeepsItems() throws {
        let configuration = KeychainConfiguration.unique()
        let client = KeychainClient.live(configuration: configuration)
        let payload = Data(TestStorageKey.session.utf8)
        try client.save(TestStorageKey.session, payload)
        defer { try? client.delete(TestStorageKey.session) }

        #expect(KeychainClient.migrateLegacyMacItemsIfNeeded(configuration: configuration) == 0)
        #expect(try client.load(TestStorageKey.session) == payload)
    }
}

private enum Constants {
    static let migrated = "migrated"
    static let ran = "ran"
}
