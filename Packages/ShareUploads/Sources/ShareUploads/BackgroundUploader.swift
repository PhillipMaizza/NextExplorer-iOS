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
/// `@unchecked Sendable`: mutable state is behind `lock`; URLSession calls the delegate on its own
/// serial queue.
public final class BackgroundUploader: NSObject, @unchecked Sendable {
    public static let shared = BackgroundUploader()

    /// Every batch session's identifier starts with this, so the app knows which wake ups are its.
    static let identifierPrefix = "com.phillipmaizza.nextexplorer.uploads."
    /// A day: room for big videos on a slow or interrupted link.
    static let resourceTimeout: TimeInterval = 24 * 60 * 60

    private let root: URL
    private let notifier: UploadNotifier
    private let certificates: ClientCertificateChallengeHandler
    private let trustEvaluator: any ServerTrustEvaluating
    private let lock = NSLock()
    private var sessions: [String: URLSession] = [:]
    private var eventsCompletion: [String: () -> Void] = [:]
    private var bodies: [String: [Int: Data]] = [:]

    init(
        root: URL = BackgroundUploader.defaultRoot,
        notifier: UploadNotifier = .live,
        certificates: ClientCertificateChallengeHandler = .shared,
        trustEvaluator: any ServerTrustEvaluating = DefaultServerTrustEvaluator()
    ) {
        self.root = root
        self.notifier = notifier
        self.certificates = certificates
        self.trustEvaluator = trustEvaluator
    }

    static var defaultRoot: URL {
        (AppGroup.containerURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("SharedUploads", isDirectory: true)
    }

    /// Whether a session identifier the system hands the app belongs to these uploads.
    public static func ownsSession(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    // MARK: Starting a batch

    /// A new batch for `credentials`' server, uploading into `destination`. Add files with
    /// `stage`, then `start` it.
    public func makeBatch(credentials: SessionCredentials, destination: String) throws -> UploadBatch {
        let id = UUID().uuidString
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return UploadBatch(id: id, directory: directory, credentials: credentials, destination: destination)
    }

    /// Hands every staged file to the system. The manifest goes first: a task can finish before
    /// this returns, and finishing needs it.
    public func start(_ batch: UploadBatch) throws {
        let manifest = Manifest(
            accountID: batch.credentials.accountID,
            destination: batch.destination,
            fileNames: batch.staged.map(\.fileName),
            envelopes: batch.staged.map(\.envelopeURL.lastPathComponent),
            serverURL: batch.credentials.serverBaseURL
        )
        try manifest.save(in: batch.directory)
        let session = session(for: Self.identifierPrefix + batch.id)
        for (index, file) in batch.staged.enumerated() {
            var request = file.request
            // A background session keeps no cookie jar of its own: the session cookie rides here.
            request.setValue("\(batch.credentials.cookieName)=\(batch.credentials.cookieValue)", forHTTPHeaderField: "Cookie")
            let task = session.uploadTask(with: request, fromFile: file.envelopeURL)
            task.taskDescription = String(index)
            task.resume()
        }
    }

    /// Drops a batch that was never started (the user cancelled while files were being read).
    public func discard(_ batch: UploadBatch) {
        try? FileManager.default.removeItem(at: batch.directory)
    }

    // MARK: Waking up for a session

    /// The app's `handleEventsForBackgroundURLSession`: reconnects to the session so its pending
    /// events arrive here, and calls `completion` once they have.
    public func handleEvents(forSession identifier: String, completion: @escaping @Sendable () -> Void) {
        lock.withLock { eventsCompletion[identifier] = completion }
        _ = session(for: identifier)
    }

    /// Batches still on disk: started and not yet finished (or finished while nobody listened).
    private func pendingBatchIDs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { UUID(uuidString: $0) != nil }
    }

    /// At app launch: reconnects to every unfinished batch so its events arrive here. The Mac never
    /// wakes the app for them, so a batch that ended while the extension was gone is finished
    /// (cleaned up, notified) now.
    public func reconnectPending() {
        for id in pendingBatchIDs() {
            let directory = root.appendingPathComponent(id, isDirectory: true)
            guard Manifest.load(from: directory) != nil else {
                // Staged but never started (the extension went away mid preparation).
                try? FileManager.default.removeItem(at: directory)
                continue
            }
            _ = session(for: Self.identifierPrefix + id)
        }
    }

    /// Signing out: stops every pending upload of an account not in `accountIDs` (all of them on
    /// the last sign out) and deletes what was staged, so nothing keeps sending as an account that
    /// left.
    public func cancel(keepingAccounts accountIDs: Set<String>) {
        for id in pendingBatchIDs() {
            let directory = root.appendingPathComponent(id, isDirectory: true)
            if let manifest = Manifest.load(from: directory), accountIDs.contains(manifest.accountID) {
                continue
            }
            let identifier = Self.identifierPrefix + id
            session(for: identifier).invalidateAndCancel()
            lock.withLock { sessions[identifier] = nil }
            try? FileManager.default.removeItem(at: directory)
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

    private func finish(task: URLSessionTask, in session: URLSession, error: (any Error)?) {
        guard let batchID = batchID(of: session), let index = task.taskDescription.flatMap(Int.init) else { return }
        let directory = root.appendingPathComponent(batchID, isDirectory: true)
        let body = lock.withLock { bodies[batchID]?.removeValue(forKey: task.taskIdentifier) } ?? Data()
        let didSucceed: Bool = if error == nil, let response = task.response as? HTTPURLResponse {
            (try? UploadRequest.decodeResponse(body, response)) != nil
        } else {
            false
        }
        guard let manifest = Manifest.load(from: directory), manifest.envelopes.indices.contains(index) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(manifest.envelopes[index]))
        let results = Manifest.record(index: index, didSucceed: didSucceed, in: directory)
        guard results.count >= manifest.fileNames.count else { return }
        let failed = manifest.fileNames.indices.filter { results[$0] == false }.map { manifest.fileNames[$0] }
        notifier.batchFinished(BatchOutcome(
            uploaded: manifest.fileNames.count - failed.count,
            failedNames: failed,
            destination: manifest.destination
        ))
        try? FileManager.default.removeItem(at: directory)
        session.finishTasksAndInvalidate()
        lock.withLock { sessions[session.configuration.identifier ?? ""] = nil }
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

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let batchID = batchID(of: session) else { return }
        lock.withLock {
            // The reply is the stored file as a small JSON array; anything bigger is not it.
            let current = bodies[batchID]?[dataTask.taskIdentifier] ?? Data()
            guard current.count < 64 * 1024 else { return }
            bodies[batchID, default: [:]][dataTask.taskIdentifier] = current + data
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(task: task, in: session, error: error)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        completeEvents(of: session)
    }

    /// The last upload invalidates the session, which can land before "finished events": the
    /// system's completion handler must still be called, exactly once.
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError _: (any Error)?) {
        completeEvents(of: session)
    }

    private func completeEvents(of session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        let completion = lock.withLock { eventsCompletion.removeValue(forKey: identifier) }
        guard let completion else { return }
        DispatchQueue.main.async { completion() }
    }
}

/// One share's worth of files. Each file's envelope is written as soon as its bytes are readable
/// (`envelope(for:fileName:)`, safe from an item provider's callback), so only one copy of it
/// ever exists on disk, then `add`ed in the order the user picked them.
public struct UploadBatch: Sendable {
    public struct StagedFile: Sendable {
        let fileName: String
        let envelopeURL: URL
        let request: URLRequest
    }

    public let id: String
    let directory: URL
    let credentials: SessionCredentials
    public let destination: String
    private(set) var staged: [StagedFile] = []

    public var count: Int {
        staged.count
    }

    /// Writes `fileURL`'s upload envelope into the batch folder. `fileURL` may go right after.
    public func envelope(for fileURL: URL, fileName: String) throws -> StagedFile {
        let envelopeURL = directory.appendingPathComponent("\(UUID().uuidString).multipart")
        let request = try UploadRequest.make(
            serverURL: credentials.serverBaseURL,
            fileURL: fileURL,
            fileName: fileName,
            destination: destination,
            envelopeURL: envelopeURL
        )
        return StagedFile(fileName: fileName, envelopeURL: envelopeURL, request: request)
    }

    public mutating func add(_ file: StagedFile) {
        staged.append(file)
    }
}

/// What a batch was for, kept beside its envelopes, plus one result file per finished upload
/// (files rather than one shared list, so two processes finishing tasks never overwrite each other).
struct Manifest: Codable, Equatable {
    /// `SessionCredentials.accountID`: signing that account out cancels the batch.
    var accountID: String
    var destination: String
    var fileNames: [String]
    /// Each file's envelope, by the same index.
    var envelopes: [String]
    var serverURL: URL

    private static let fileName = "manifest.json"
    private static let resultsFolder = "results"

    func save(in directory: URL) throws {
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    static func load(from directory: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Records one upload's result and returns every result so far, by file index.
    static func record(index: Int, didSucceed: Bool, in directory: URL) -> [Int: Bool] {
        let folder = directory.appendingPathComponent(resultsFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data((didSucceed ? "1" : "0").utf8).write(to: folder.appendingPathComponent(String(index)), options: .atomic)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var results: [Int: Bool] = [:]
        for name in names {
            guard let index = Int(name), let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { continue }
            results[index] = data == Data("1".utf8)
        }
        return results
    }
}

public struct BatchOutcome: Equatable, Sendable {
    public var uploaded: Int
    public var failedNames: [String]
    public var destination: String
}
