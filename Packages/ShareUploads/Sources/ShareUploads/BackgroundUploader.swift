import CoreModels
import FilesClient
import Foundation
import NetworkClient

/// Uploads files shared from other apps in a background URLSession, so they keep going after the
/// share sheet closes and while the device sleeps. Each batch is staged in the App Group container
/// (the system reads the upload bodies from there) with a manifest beside it, so whichever process
/// receives the session's events (the extension while it lives, the app once the system wakes it)
/// can finish the batch: delete what was sent and post one notification for the lot.
///
/// A batch with failures keeps those files' envelopes (and a `finished` marker so it is reported
/// once) until the user retries them or `failedRetention` passes. Dismissing the notification
/// never deletes anything.
///
/// `@unchecked Sendable`: mutable state is behind `lock`; URLSession calls the delegate on its own
/// serial queue.
public final class BackgroundUploader: NSObject, @unchecked Sendable {
    public static let shared = BackgroundUploader()

    /// Every batch session's identifier starts with this, so the app knows which wake ups are its.
    static let identifierPrefix = "com.phillipmaizza.nextexplorer.uploads."
    /// A day: room for big videos on a slow or interrupted link.
    static let resourceTimeout: TimeInterval = 24 * 60 * 60
    /// A started batch with no live task and a staged one never started are leftovers after this.
    static let staleAge: TimeInterval = 60 * 60
    /// Another process (the extension) may still own a batch this young, so the app leaves it alone.
    static let youngAge: TimeInterval = 5 * 60
    /// The extension touches the manifest while it starts tasks: one touched this recently is young
    /// whatever its start date says.
    static let heartbeatAge: TimeInterval = 2 * 60
    /// How long the failed files of a finished batch stay on disk for a retry.
    static let failedRetention: TimeInterval = 3 * 24 * 60 * 60
    /// After reconnecting, how long pending events get to arrive before a batch counts as abandoned.
    static let abandonGrace: TimeInterval = 30
    /// The system gives a wake up about 30 seconds; its completion handler is called before that.
    static let eventsTimeout: TimeInterval = 25
    static let signInFlagPrefix = "shareUploads.needsSignIn."

    private enum Constants {
        static let maxReplyBytes = 64 * 1024
        static let removingPrefix = ".removing-"
        static let cookieHeader = "Cookie"
    }

    let root: URL
    let notifier: UploadNotifier
    let defaults: UserDefaults
    let now: @Sendable () -> Date
    private let availableCapacity: @Sendable (URL) -> Int64?
    private let startTasks: (@Sendable (_ sessionIdentifier: String, _ specs: [UploadTaskSpec]) -> Void)?
    private let certificates: ClientCertificateChallengeHandler
    private let trustEvaluator: any ServerTrustEvaluating
    private let events: EventsEnvironment
    private let lock = NSLock()
    private var sessions: [String: URLSession] = [:]
    private var eventsRegistrations: [String: EventsRegistration] = [:]
    private var bodies: [String: [Int: Data]] = [:]

    init(
        root: URL = BackgroundUploader.defaultRoot,
        notifier: UploadNotifier = .live,
        certificates: ClientCertificateChallengeHandler = .shared,
        trustEvaluator: any ServerTrustEvaluating = DefaultServerTrustEvaluator(),
        defaults: UserDefaults = AppGroup.defaults,
        now: @escaping @Sendable () -> Date = { Date() },
        availableCapacity: @escaping @Sendable (URL) -> Int64? = DiskSpace.availableCapacity,
        events: EventsEnvironment = .live,
        startTasks: (@Sendable (_ sessionIdentifier: String, _ specs: [UploadTaskSpec]) -> Void)? = nil
    ) {
        self.events = events
        self.root = root
        self.notifier = notifier
        self.certificates = certificates
        self.trustEvaluator = trustEvaluator
        self.defaults = defaults
        self.now = now
        self.availableCapacity = availableCapacity
        self.startTasks = startTasks
    }

    static var defaultRoot: URL {
        (AppGroup.containerURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("SharedUploads", isDirectory: true)
    }

    /// Whether a session identifier the system hands the app belongs to these uploads.
    public static func ownsSession(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    func directory(of batchID: String) -> URL {
        root.appendingPathComponent(batchID, isDirectory: true)
    }

    // MARK: Starting a batch

    /// A new batch for `credentials`' server, uploading into `destination`. Add files with
    /// `stage`, then `start` it.
    public func makeBatch(credentials: SessionCredentials, destination: String) throws -> UploadBatch {
        let id = UUID().uuidString
        let directory = directory(of: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return UploadBatch(
            id: id, directory: directory, credentials: credentials, destination: destination,
            availableCapacity: availableCapacity
        )
    }

    /// Hands every staged file to the system. The manifest goes first: a task can finish before
    /// this returns, and finishing needs it.
    public func start(_ batch: UploadBatch) throws {
        let manifest = Manifest(
            accountID: batch.credentials.accountID,
            destination: batch.destination,
            fileNames: batch.staged.map(\.fileName),
            envelopes: batch.staged.map(\.envelopeURL.lastPathComponent),
            contentTypes: batch.staged.map(\.contentType),
            serverURL: batch.credentials.serverBaseURL,
            startedAt: now()
        )
        try manifest.save(in: batch.directory)
        submit(Array(batch.staged.indices), of: manifest, in: batch.directory, credentials: batch.credentials, batchID: batch.id)
    }

    private func submit(
        _ indices: [Int], of manifest: Manifest, in directory: URL, credentials: SessionCredentials, batchID: String
    ) {
        let specs = Self.taskSpecs(for: indices, of: manifest, in: directory, credentials: credentials)
        let identifier = Self.identifierPrefix + batchID
        Manifest.touch(directory, at: now())
        if let startTasks {
            startTasks(identifier, specs)
            return
        }
        let session = session(for: identifier)
        for spec in specs {
            Manifest.touch(directory, at: now())
            let task = session.uploadTask(with: spec.request, fromFile: spec.envelopeURL)
            task.taskDescription = String(spec.index)
            task.resume()
        }
    }

    static func taskSpecs(
        for indices: [Int], of manifest: Manifest, in directory: URL, credentials: SessionCredentials
    ) -> [UploadTaskSpec] {
        indices.map { index in
            var request = UploadRequest.request(serverURL: manifest.serverURL, contentType: manifest.contentTypes[index])
            // A background session keeps no cookie jar of its own: the session cookie rides here.
            request.setValue("\(credentials.cookieName)=\(credentials.cookieValue)", forHTTPHeaderField: Constants.cookieHeader)
            return UploadTaskSpec(
                index: index, request: request, envelopeURL: directory.appendingPathComponent(manifest.envelopes[index])
            )
        }
    }

    /// Drops a batch that was never started (the user cancelled while files were being read).
    public func discard(_ batch: UploadBatch) {
        try? FileManager.default.removeItem(at: batch.directory)
    }

    // MARK: Failed files

    /// Sends the files of a finished batch that failed again, with `credentials`' current session
    /// cookie, and returns how many went out. A later finish reports the batch once more.
    @discardableResult
    public func retryFailed(batchID: String, credentials: SessionCredentials) -> Int {
        guard UUID(uuidString: batchID) != nil else { return 0 }
        let directory = directory(of: batchID)
        guard var manifest = Manifest.load(from: directory), manifest.accountID == credentials.accountID else { return 0 }
        let results = Manifest.results(in: directory)
        let failed = manifest.fileNames.indices.filter {
            results[$0]?.cause != nil
                && FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifest.envelopes[$0]).path)
        }
        guard !failed.isEmpty else { return 0 }
        manifest.startedAt = now()
        guard (try? manifest.save(in: directory)) != nil else { return 0 }
        Manifest.clearResults(failed, in: directory)
        Manifest.releaseClaim(directory)
        clearNeedsSignIn(accountID: credentials.accountID)
        submit(failed, of: manifest, in: directory, credentials: credentials, batchID: batchID)
        return failed.count
    }

    /// The account a batch was uploading for, so a notification only has to carry the batch id.
    public func accountID(ofBatch batchID: String) -> String? {
        guard UUID(uuidString: batchID) != nil else { return nil }
        return Manifest.load(from: directory(of: batchID))?.accountID
    }

    // MARK: Sign in flags

    /// Accounts an upload was refused for (401) since they last signed in, for the app to act on.
    public func accountsNeedingSignIn() -> Set<String> {
        Set(defaults.dictionaryRepresentation().keys.compactMap { key in
            key.hasPrefix(Self.signInFlagPrefix) ? String(key.dropFirst(Self.signInFlagPrefix.count)) : nil
        })
    }

    public func clearNeedsSignIn(accountID: String) {
        defaults.removeObject(forKey: Self.signInFlagPrefix + accountID)
    }

    private func flagNeedsSignIn(accountID: String) {
        defaults.set(true, forKey: Self.signInFlagPrefix + accountID)
    }

    // MARK: Waking up for a session

    /// The app's `handleEventsForBackgroundURLSession`: reconnects to the session so its pending
    /// events arrive here, and calls `completion` once they have. Nothing is held when there is
    /// nothing to wait for (a batch that is gone or already reported has no events left to run).
    public func handleEvents(forSession identifier: String, completion: @escaping @Sendable () -> Void) {
        let token = registerEvents(forSession: identifier, completion: completion)
        let directory = directory(of: String(identifier.dropFirst(Self.identifierPrefix.count)))
        session(for: identifier).getAllTasks { [self] tasks in
            let hasManifest = Manifest.load(from: directory) != nil
            let isClaimed = Manifest.claimedAt(directory) != nil
            if Self.shouldCompleteEventsImmediately(liveTaskCount: tasks.count, hasManifest: hasManifest, isClaimed: isClaimed) {
                completeEvents(identifier: identifier, token: token)
            }
        }
    }

    /// Holds the system's completion handler for `identifier` and arms its safety timer. A second
    /// wake up for the same session displaces the first, whose handler is called right away rather
    /// than lost, and the timer only ever completes its own registration.
    @discardableResult
    func registerEvents(forSession identifier: String, completion: @escaping @Sendable () -> Void) -> UUID {
        let token = UUID()
        let cancelTimer = events.schedule(Self.eventsTimeout) { [self] in
            completeEvents(identifier: identifier, token: token)
        }
        let displaced = lock.withLock {
            eventsRegistrations.updateValue(
                EventsRegistration(token: token, completion: completion, cancelTimer: cancelTimer), forKey: identifier
            )
        }
        if let displaced {
            displaced.cancelTimer()
            events.deliver(displaced.completion)
        }
        return token
    }

    static func shouldCompleteEventsImmediately(liveTaskCount: Int, hasManifest: Bool, isClaimed: Bool) -> Bool {
        liveTaskCount == 0 && (!hasManifest || isClaimed)
    }

    /// Batches still on disk: started and not yet finished (or finished while nobody listened).
    private func pendingBatchIDs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { UUID(uuidString: $0) != nil }
    }

    enum PendingAction: Equatable {
        /// Nothing to do now: another process owns it, or it is reported and waiting out its retention.
        case wait
        case finish
        case expire
        case reconnect
    }

    /// Young: started a moment ago, or its owner touched the manifest a moment ago.
    static func isYoung(startedAt: Date, touchedAt: Date?, now: Date) -> Bool {
        if now.timeIntervalSince(startedAt) < youngAge {
            return true
        }
        guard let touchedAt else { return false }
        let sinceTouch = now.timeIntervalSince(touchedAt)
        return sinceTouch >= 0 && sinceTouch < heartbeatAge
    }

    static func pendingAction(
        startedAt: Date, touchedAt: Date? = nil, resultCount: Int, fileCount: Int, claimedAt: Date?, now: Date
    ) -> PendingAction {
        if let claimedAt {
            return now.timeIntervalSince(claimedAt) > failedRetention ? .expire : .wait
        }
        if resultCount >= fileCount {
            return .finish
        }
        return isYoung(startedAt: startedAt, touchedAt: touchedAt, now: now) ? .wait : .reconnect
    }

    /// A started batch no task is running for, long after it started, will never complete by itself.
    static func isAbandoned(liveTaskCount: Int, startedAt: Date, now: Date) -> Bool {
        liveTaskCount == 0 && now.timeIntervalSince(startedAt) > staleAge
    }

    /// When the app launches or becomes active: reconnects to every unfinished batch so its events
    /// arrive here, reports and cleans up batches that ended while nobody listened (the Mac never
    /// wakes the app for them), and drops leftovers. Safe to call repeatedly: finishing a batch is
    /// claimed once, and batches the extension may still own are left alone.
    public func reconnectPending() {
        for id in pendingBatchIDs() {
            let directory = directory(of: id)
            guard let manifest = Manifest.load(from: directory) else {
                // Staged but never started (the extension went away mid preparation). A recent one
                // may still be filling in another process, so only old leftovers go.
                if Self.isStale(directory, now: now()) {
                    try? FileManager.default.removeItem(at: directory)
                }
                continue
            }
            let action = Self.pendingAction(
                startedAt: manifest.startedAt,
                touchedAt: Manifest.touchedAt(directory),
                resultCount: Manifest.results(in: directory).count,
                fileCount: manifest.fileNames.count,
                claimedAt: Manifest.claimedAt(directory),
                now: now()
            )
            switch action {
            case .wait:
                continue
            case .expire:
                try? FileManager.default.removeItem(at: directory)
            case .finish:
                finishBatch(id: id, manifest: manifest)
            case .reconnect:
                reconnect(batchID: id, manifest: manifest)
            }
        }
    }

    private func reconnect(batchID: String, manifest: Manifest) {
        let session = session(for: Self.identifierPrefix + batchID)
        session.getAllTasks { [self] tasks in
            guard Self.isAbandoned(liveTaskCount: tasks.count, startedAt: manifest.startedAt, now: now()) else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.abandonGrace) { [self] in
                session.getAllTasks { [self] tasks in
                    if tasks.isEmpty {
                        abandonOutstanding(batchID: batchID)
                    }
                }
            }
        }
    }

    /// Finishes a batch whose remaining files will never report: they count as failed, as
    /// `abandoned` so an event that arrives late can still put the record right.
    func abandonOutstanding(batchID: String) {
        let directory = directory(of: batchID)
        guard let manifest = Manifest.load(from: directory), Manifest.claimedAt(directory) == nil else { return }
        let results = Manifest.results(in: directory)
        for index in manifest.fileNames.indices where results[index] == nil {
            Manifest.record(index: index, result: .abandoned, in: directory)
        }
        finishBatch(id: batchID, manifest: manifest)
    }

    /// Removes a reported batch in one step: the folder is renamed away first, so a second process
    /// that is still finishing the same batch can't claim again in the folder that is being emptied.
    static func removeFinished(_ directory: URL) {
        let tombstone = directory.deletingLastPathComponent()
            .appendingPathComponent(Constants.removingPrefix + UUID().uuidString, isDirectory: true)
        let target = (try? FileManager.default.moveItem(at: directory, to: tombstone)) == nil ? directory : tombstone
        try? FileManager.default.removeItem(at: target)
    }

    static func isStale(_ directory: URL, now: Date) -> Bool {
        let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modified = values?.contentModificationDate else { return true }
        return now.timeIntervalSince(modified) > staleAge
    }

    /// Signing out: stops every pending upload of an account not in `accountIDs` (all of them on
    /// the last sign out) and deletes what was staged, so nothing keeps sending as an account that
    /// left. The batch folder goes first so the cancelled tasks' callbacks find nothing to report.
    public func cancel(keepingAccounts accountIDs: Set<String>) {
        for id in pendingBatchIDs() {
            let directory = directory(of: id)
            if let manifest = Manifest.load(from: directory) {
                if accountIDs.contains(manifest.accountID) {
                    continue
                }
            } else if !Self.isStale(directory, now: now()) {
                // Still being filled in by the extension: not started, so nothing to cancel yet.
                continue
            }
            try? FileManager.default.removeItem(at: directory)
            let identifier = Self.identifierPrefix + id
            session(for: identifier).invalidateAndCancel()
            lock.withLock {
                sessions[identifier] = nil
                bodies[id] = nil
            }
        }
        for accountID in accountsNeedingSignIn().subtracting(accountIDs) {
            clearNeedsSignIn(accountID: accountID)
        }
    }

    private func session(for identifier: String) -> URLSession {
        lock.withLock {
            if let existing = sessions[identifier] {
                return existing
            }
            let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
            configuration.sharedContainerIdentifier = AppGroup.identifier
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            // A handshake the server refuses is retried, not failed: cap the whole upload so a
            // batch that can't go through still ends, says so and cleans up.
            configuration.timeoutIntervalForResource = Self.resourceTimeout
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            sessions[identifier] = session
            return session
        }
    }

    private func batchID(of session: URLSession) -> String? {
        guard let identifier = session.configuration.identifier, Self.ownsSession(identifier) else { return nil }
        return String(identifier.dropFirst(Self.identifierPrefix.count))
    }

    // MARK: Finishing

    static func result(response: HTTPURLResponse?, body: Data, error: (any Error)?) -> UploadResult {
        if error == nil, let response, (try? UploadRequest.decodeResponse(body, response)) != nil {
            return .success
        }
        return .failure(.classify(statusCode: response?.statusCode, error: error))
    }

    /// Records one file's result and finishes the batch when it was the last. A failed file keeps
    /// its envelope so it can be retried; a sent one does not. A success that arrives for a batch
    /// already reported with that file as failed (an abandoned file whose event was only late)
    /// corrects the record and reports the batch again.
    func complete(batchID: String, index: Int, result: UploadResult) {
        let directory = directory(of: batchID)
        guard let manifest = Manifest.load(from: directory), manifest.envelopes.indices.contains(index) else { return }
        let isCorrection = result == .success
            && Manifest.claimedAt(directory) != nil
            && Manifest.results(in: directory)[index]?.cause != nil
        switch result {
        case .success:
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(manifest.envelopes[index]))
        case .failure(.unauthorized):
            flagNeedsSignIn(accountID: manifest.accountID)
        case .failure, .abandoned:
            break
        }
        let results = Manifest.record(index: index, result: result, in: directory)
        if isCorrection {
            report(id: batchID, manifest: manifest)
            return
        }
        guard results.count >= manifest.fileNames.count else { return }
        finishBatch(id: batchID, manifest: manifest)
    }

    /// Reports the batch once, however many processes get here: the claim marker is exclusive.
    func finishBatch(id: String, manifest: Manifest) {
        guard Manifest.claim(directory(of: id)) else { return }
        report(id: id, manifest: manifest)
    }

    private func report(id: String, manifest: Manifest) {
        let directory = directory(of: id)
        let results = Manifest.results(in: directory)
        let failures: [FailedUpload] = manifest.fileNames.indices.compactMap { index in
            results[index]?.cause.map { FailedUpload(name: manifest.fileNames[index], cause: $0) }
        }
        notifier.batchFinished(BatchOutcome(
            batchID: id,
            accountID: manifest.accountID,
            host: manifest.serverURL.host ?? manifest.serverURL.absoluteString,
            destination: manifest.destination,
            uploaded: manifest.fileNames.count - failures.count,
            failures: failures
        ))
        if failures.isEmpty {
            Self.removeFinished(directory)
        }
        let identifier = Self.identifierPrefix + id
        let session = lock.withLock { () -> URLSession? in
            bodies[id] = nil
            return sessions.removeValue(forKey: identifier)
        }
        session?.finishTasksAndInvalidate()
    }
}

extension BackgroundUploader: URLSessionDataDelegate {
    public func urlSession(
        _: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let answer = certificates.handle(challenge) {
            return answer
        }
        return await trustEvaluator.evaluate(challenge)
    }

    public func urlSession(
        _ session: URLSession, task _: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await urlSession(session, didReceive: challenge)
    }

    /// The upload endpoint never redirects. Following one would resend the session cookie (a header
    /// set by hand survives redirects) and the file to wherever it points, so the upload fails instead.
    public func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let batchID = batchID(of: session) else { return }
        lock.withLock {
            // The reply is the stored file as a small JSON array; anything bigger is not it.
            let current = bodies[batchID]?[dataTask.taskIdentifier] ?? Data()
            guard current.count < Constants.maxReplyBytes else { return }
            bodies[batchID, default: [:]][dataTask.taskIdentifier] = current + data
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let batchID = batchID(of: session), let index = task.taskDescription.flatMap(Int.init) else { return }
        let body = lock.withLock { bodies[batchID]?.removeValue(forKey: task.taskIdentifier) } ?? Data()
        let result = Self.result(response: task.response as? HTTPURLResponse, body: body, error: error)
        complete(batchID: batchID, index: index, result: result)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        completeEvents(identifier: identifier)
    }

    /// The last upload invalidates the session, which can land before "finished events": the
    /// system's completion handler must still be called, exactly once.
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError _: (any Error)?) {
        guard let identifier = session.configuration.identifier else { return }
        completeEvents(identifier: identifier)
    }

    /// Calls the system's completion handler for `identifier`, once. With a `token`, only the
    /// registration that owns it completes: a stale timer or task query never ends a newer wake up.
    func completeEvents(identifier: String, token: UUID? = nil) {
        let registration = lock.withLock { () -> EventsRegistration? in
            guard let current = eventsRegistrations[identifier], token == nil || current.token == token else { return nil }
            return eventsRegistrations.removeValue(forKey: identifier)
        }
        guard let registration else { return }
        registration.cancelTimer()
        events.deliver(registration.completion)
    }
}

/// The system's wake up completion handler for one session, with the timer that guarantees it is
/// called before the system's deadline.
private struct EventsRegistration: Sendable {
    let token: UUID
    let completion: @Sendable () -> Void
    let cancelTimer: @Sendable () -> Void
}

/// The two things wake up handling needs from the outside, so tests can run them by hand.
struct EventsEnvironment: Sendable {
    /// Runs `work` after `delay`; the returned closure cancels it.
    var schedule: @Sendable (_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) -> @Sendable () -> Void
    /// Calls the system's handler (UIKit expects the main thread).
    var deliver: @Sendable (_ work: @escaping @Sendable () -> Void) -> Void

    static let live = EventsEnvironment(
        schedule: { delay, work in
            // DispatchWorkItem is documented as thread safe for cancel().
            nonisolated(unsafe) let item = DispatchWorkItem(block: work)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        },
        deliver: { work in DispatchQueue.main.async(execute: work) }
    )
}

/// One upload to hand to a session: the file's index in its batch, the request and its envelope.
struct UploadTaskSpec: Equatable, Sendable {
    var index: Int
    var request: URLRequest
    var envelopeURL: URL
}
