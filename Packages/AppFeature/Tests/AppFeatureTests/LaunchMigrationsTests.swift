@testable import AppFeature
import ComposableArchitecture
import Foundation
import Testing

@Suite("Launch migrations")
struct LaunchMigrationsTests {
    private func steps(_ events: LockIsolated<[String]>) -> LaunchMigrations.Steps {
        LaunchMigrations.Steps(
            begin: { events.withValue { $0.append("begin") } },
            sharedGroup: { events.withValue { $0.append("sharedGroup") } },
            legacyMac: { events.withValue { $0.append("legacyMac") } },
            finish: { events.withValue { $0.append("finish") } }
        )
    }

    @Test("Reads are held before start returns, then both migrations run in order and release them")
    func orderingSeam() async {
        let events = LockIsolated<[String]>([])

        let task = LaunchMigrations.start(steps: steps(events))
        #expect(events.value.first == "begin", "the hold is in place before any caller can read")
        await task.value

        #expect(events.value == ["begin", "sharedGroup", "legacyMac", "finish"])
    }

    @Test("The migrations do not run on the calling thread")
    func runsOffTheCaller() async {
        let callerIsMain = LockIsolated<Bool?>(nil)
        let task = LaunchMigrations.start(steps: LaunchMigrations.Steps(
            begin: {},
            sharedGroup: { callerIsMain.setValue(Thread.isMainThread) },
            legacyMac: {},
            finish: {}
        ))
        await task.value
        #expect(callerIsMain.value == false)
    }
}
