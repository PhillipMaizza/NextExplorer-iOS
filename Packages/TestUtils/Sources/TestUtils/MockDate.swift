import Foundation
import Synchronization

public enum MockDate {
    public static let date = Date(timeIntervalSince1970: 1_700_000_000)
}

public enum TestID {
    private static let counter = Mutex(0)
    private static let processID = Int(ProcessInfo.processInfo.processIdentifier)

    private static func next() -> Int {
        counter.withLock { value in
            value += 1
            return value
        }
    }

    /// A name no other call in the process shares, for temporary directories and store scopes.
    public static func name() -> String {
        "test-\(processID)-\(next())"
    }

    /// A UUID no other call in the process shares.
    public static func uuid() -> UUID {
        UUID(uuidString: "00000000-0000-0000-" + String(format: "%04x", processID & 0xFFFF) + "-" + String(
            format: "%012d",
            next()
        )) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }
}
