import Foundation
@testable import Keychain
import Testing
import TestUtils

@Suite("Keychain migration gate")
struct KeychainMigrationGateTests {
    private enum Constants {
        /// Long enough that a wait which did not end would be the test's failure, not its outcome.
        static let neverEnding: TimeInterval = 24 * 60 * 60
    }

    @Test("a read waits for the migration that began before it and runs after it finished", .timeLimit(.minutes(1)))
    func readWaitsForMigration() async {
        let gate = KeychainMigrationGate()
        let events = LockIsolated<[String]>([])
        let (readerStarted, signalReader) = AsyncStream.makeStream(of: Void.self)
        let client = KeychainClient(
            save: { _, _ in },
            load: { _ in
                events.withValue { $0.append("read") }
                return nil
            },
            delete: { _ in }
        ).waiting(for: gate)

        gate.begin()
        let reader = Task.detached {
            signalReader.yield()
            return try? client.load(TestStorageKey.storedSessions)
        }
        for await _ in readerStarted {
            break
        }
        events.withValue { $0.append("migrated") }
        gate.finish()
        _ = await reader.value

        #expect(events.value == ["migrated", "read"], "the read never saw the half moved keychain")
    }

    @Test("nothing waits when no migration was begun", .timeLimit(.minutes(1)))
    func noMigrationNoWait() async {
        let gate = KeychainMigrationGate()
        await confirmation("the wait returned instead of blocking") { returned in
            gate.waitUntilFinished(maxWait: Constants.neverEnding)
            returned()
        }
    }

    @Test("a finished migration lets later reads straight through", .timeLimit(.minutes(1)))
    func finishedMigrationNoWait() async {
        let gate = KeychainMigrationGate()
        gate.begin()
        gate.finish()
        await confirmation("the wait returned instead of blocking") { returned in
            gate.waitUntilFinished(maxWait: Constants.neverEnding)
            returned()
        }
    }

    @Test("a migration that never finishes releases the read once the maximum wait is spent", .timeLimit(.minutes(1)))
    func waitIsBounded() {
        let gate = KeychainMigrationGate()
        gate.begin()
        gate.waitUntilFinished(maxWait: 0)
        gate.finish()
        gate.waitUntilFinished(maxWait: Constants.neverEnding)
    }
}
