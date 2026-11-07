import Foundation
@testable import Keychain
import Testing

@Suite("Keychain migration gate")
struct KeychainMigrationGateTests {
    private enum Constants {
        static let shortWait: TimeInterval = 0.05
        static let migrationDuration: Duration = .milliseconds(100)
        static let generousWait: TimeInterval = 5
        static let returnsPromptly: TimeInterval = 1
    }

    @Test("a read waits for the migration that began before it and runs after it finished")
    func readWaitsForMigration() async {
        let gate = KeychainMigrationGate()
        let events = LockIsolated<[String]>([])
        let client = KeychainClient(
            save: { _, _ in },
            load: { _ in
                events.withValue { $0.append("read") }
                return nil
            },
            delete: { _ in }
        ).waiting(for: gate)

        gate.begin()
        let migration = Task.detached {
            try? await Task.sleep(for: Constants.migrationDuration)
            events.withValue { $0.append("migrated") }
            gate.finish()
        }
        _ = await Task.detached { try? client.load("storedSessions") }.value
        await migration.value

        #expect(events.value == ["migrated", "read"])
    }

    @Test("nothing waits when no migration was begun")
    func noMigrationNoWait() {
        let gate = KeychainMigrationGate()
        let start = Date()
        gate.waitUntilFinished(maxWait: Constants.generousWait)
        #expect(Date().timeIntervalSince(start) < Constants.returnsPromptly)
    }

    @Test("a migration that never finishes releases the read after the maximum wait")
    func waitIsBounded() {
        let gate = KeychainMigrationGate()
        gate.begin()
        let start = Date()
        gate.waitUntilFinished(maxWait: Constants.shortWait)
        #expect(Date().timeIntervalSince(start) >= Constants.shortWait)
    }
}

private final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func withValue(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}
