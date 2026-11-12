import CoreModels
import Foundation
@testable import ShareUploads
import UserNotifications
import TestUtils

enum TestClock {
    /// A fixed moment; tests move the clock with offsets from it.
    static let reference = MockDate.date.addingTimeInterval(100_000_000)
}

final class RecordingNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [BatchOutcome] = []

    var outcomes: [BatchOutcome] {
        lock.withLock { recorded }
    }

    var notifier: UploadNotifier {
        UploadNotifier { [self] outcome in lock.withLock { recorded.append(outcome) } }
    }
}

/// The notification center as a test sees it: what was posted and which identifiers were removed.
final class RecordingCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var added: [UNNotificationRequest] = []
    private var removals: [[String]] = []
    private var registered: [Set<UNNotificationCategory>] = []

    var requests: [UNNotificationRequest] {
        lock.withLock { added }
    }

    var removedIdentifiers: [[String]] {
        lock.withLock { removals }
    }

    var categorySets: [Set<UNNotificationCategory>] {
        lock.withLock { registered }
    }

    var center: NotificationCenterClient {
        NotificationCenterClient(
            add: { [self] request in lock.withLock { added.append(request) } },
            remove: { [self] identifiers in lock.withLock { removals.append(identifiers) } },
            setCategories: { [self] categories in lock.withLock { registered.append(categories) } }
        )
    }
}

/// What each batch's background session is "still running", answered at once.
final class FakeTasks: @unchecked Sendable {
    private let lock = NSLock()
    private var live: [String: LiveTasks] = [:]

    func set(_ tasks: LiveTasks, forBatch batchID: String) {
        lock.withLock { live[BackgroundUploader.identifierPrefix + batchID] = tasks }
    }

    var query: @Sendable (String, @escaping @Sendable (LiveTasks) -> Void) -> Void {
        { [self] identifier, completion in
            completion(lock.withLock { live[identifier] } ?? LiveTasks(count: 0, indexes: []))
        }
    }
}

final class RecordingStarter: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(identifier: String, specs: [UploadTaskSpec])] = []

    var started: [(identifier: String, specs: [UploadTaskSpec])] {
        lock.withLock { recorded }
    }

    var start: @Sendable (String, [UploadTaskSpec]) -> Void {
        { [self] identifier, specs in lock.withLock { recorded.append((identifier, specs)) } }
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = TestClock.reference

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

/// Stands in for the timer and the main thread of wake up handling: timers run only when a test
/// fires them, deliveries are recorded in order.
final class FakeEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var timers: [Int: @Sendable () -> Void] = [:]
    private var nextTimer = 0
    private var delivered = 0
    private var delays: [TimeInterval] = []

    var pendingTimers: Int {
        lock.withLock { timers.count }
    }

    var scheduledDelays: [TimeInterval] {
        lock.withLock { delays }
    }

    var environment: EventsEnvironment {
        EventsEnvironment(
            schedule: { [self] delay, work in
                let id = lock.withLock { () -> Int in
                    nextTimer += 1
                    timers[nextTimer] = work
                    delays.append(delay)
                    return nextTimer
                }
                return { [self] in lock.withLock { timers[id] = nil } }
            },
            deliver: { work in work() }
        )
    }

    /// Runs every timer still armed, oldest first, as the real clock would have.
    func fireTimers() {
        let due = lock.withLock { () -> [@Sendable () -> Void] in
            let sorted = timers.sorted { $0.key < $1.key }.map(\.value)
            timers = [:]
            return sorted
        }
        for work in due {
            work()
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    var call: @Sendable () -> Void {
        { [self] in lock.withLock { value += 1 } }
    }
}

struct Harness {
    let root: URL
    let defaults: UserDefaults
    let suite: String
    let recorder = RecordingNotifier()
    let starter = RecordingStarter()
    let clock = Clock()
    let events = FakeEvents()
    let center = RecordingCenter()
    let tasks = FakeTasks()
    let uploader: BackgroundUploader

    init(
        availableCapacity: @escaping @Sendable (URL) -> Int64? = { _ in nil },
        removeEnvelope: @escaping @Sendable (URL) -> Void = { try? FileManager.default.removeItem(at: $0) }
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ShareUploadsHarness-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ShareUploadsHarness-\(TestID.uuid().uuidString)"
        guard let suiteDefaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileReadUnknown) }
        defaults = suiteDefaults
        let clock = clock
        uploader = BackgroundUploader(
            root: root,
            notifier: recorder.notifier,
            notifications: center.center,
            defaults: suiteDefaults,
            now: { clock.now },
            availableCapacity: availableCapacity,
            events: events.environment,
            startTasks: starter.start,
            queryTasks: tasks.query,
            removeEnvelope: removeEnvelope
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    static let credentials = SessionCredentials(
        serverBaseURL: URL(string: TestHost.serverURLString) ?? URL(fileURLWithPath: "/"),
        authMode: .local,
        cookieName: TestSession.cookieName,
        cookieValue: TestSession.uploadCookieValue,
        cookieDomain: TestHost.server,
        cookiePath: "/",
        cookieIsSecure: true,
        expiresAt: nil,
        username: TestAccount.username
    )

    /// A started batch of `names` on disk: manifest, one envelope per file, no results yet.
    @discardableResult
    func makeBatch(
        names: [String] = [TestFile.aPhoto, TestFile.bPhoto],
        accountID: String = Harness.credentials.accountID,
        startedAt: Date = TestClock.reference
    ) throws -> (id: String, directory: URL, manifest: Manifest) {
        let id = TestID.uuid().uuidString
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelopes = names.indices.map { "\($0).multipart" }
        for envelope in envelopes {
            try Data("envelope".utf8).write(to: directory.appendingPathComponent(envelope))
        }
        let manifest = Manifest(
            accountID: accountID,
            destination: TestPath.photos2026,
            fileNames: names,
            envelopes: envelopes,
            contentTypes: names.map { _ in "multipart/form-data; boundary=B" },
            serverURL: Harness.credentials.serverBaseURL,
            startedAt: startedAt
        )
        try manifest.save(in: directory)
        return (id, directory, manifest)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
