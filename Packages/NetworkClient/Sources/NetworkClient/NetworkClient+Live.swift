import Dependencies
import Foundation

private enum Constants {
    /// A dead or far-away server shouldn't hang an interactive request for the URLSession
    /// default of 60s — the launch session check and every tap has to give up sooner.
    static let interactiveRequestTimeout: TimeInterval = 15
    /// Opportunistic page fetches (PDF thumbnails) can be genuinely slow; let them run to
    /// the URLSession default rather than sharing the interactive budget.
    static let lowPriorityRequestTimeout: TimeInterval = 60
    /// Connection cap for the low priority session — small, so however many fetches the UI
    /// kicks off they never take slots from the main session's 6 per host interactive pool.
    static let lowPriorityMaxConnectionsPerHost = 2
    /// File downloads (previews, offline sync) stream to disk and can take a long time: a big file,
    /// a slow link, a server that buffers before its first byte, or several concurrent transfers where
    /// one waits behind the others. `timeoutIntervalForRequest` is an *inactivity* timer (reset on
    /// every packet), so it never fires mid transfer; it only bounds a genuinely stalled connection.
    /// The interactive 15s value is right for a tap sized API call but wrong here: it was timing large
    /// downloads out (NSURLErrorTimedOut, -1001) and making them appear to crawl as they retried.
    /// A file actively transferring resets this on every packet, so a real download of any size never
    /// hits it (downloads run one at a time, so there is always a packet flowing). It fires only on a
    /// genuinely stalled socket, most importantly a stale keep alive connection the server already
    /// dropped: 60s bounds how long such a dead connection stalls before failing, instead of hanging
    /// for minutes. Connections are also flushed before each batch (see `flushDownloadConnections`).
    static let downloadRequestTimeout: TimeInterval = 60
    static let downloadTempFilePrefix = "download-"
}

public extension NetworkClient {
    /// Ceiling on a response buffered by `send`. The `send` path exists only for JSON control
    /// responses (listings, share lists, editor content) — anything file-sized goes through
    /// `download`, which streams to disk. 32 MB is far above any legitimate JSON payload while
    /// still cutting off a hostile server trying to exhaust memory here.
    static let defaultMaxInMemoryResponseBytes = 32 * 1024 * 1024

    static func live(
        trustEvaluator: ServerTrustEvaluating = DefaultServerTrustEvaluator(),
        cookieStorage: HTTPCookieStorage = .shared,
        protocolClasses: [AnyClass] = [],
        maxInMemoryResponseBytes: Int = NetworkClient.defaultMaxInMemoryResponseBytes
    ) -> NetworkClient {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = Constants.interactiveRequestTimeout
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses
        }

        let delegate = URLSessionAuthDelegate(trustEvaluator: trustEvaluator)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        // A second session for opportunistic background fetches (PDF thumbnail page
        // downloads). Its own connection pool, capped low, so however many the UI kicks off
        // they can't take slots from the main session's interactive traffic. Deliberately
        // NOT `networkServiceType = .background` — that lets the system defer requests
        // indefinitely, even in the foreground, so thumbnails would just never appear.
        let lowPriorityConfiguration = URLSessionConfiguration.default
        lowPriorityConfiguration.httpCookieStorage = cookieStorage
        lowPriorityConfiguration.httpCookieAcceptPolicy = .always
        lowPriorityConfiguration.httpShouldSetCookies = true
        lowPriorityConfiguration.httpMaximumConnectionsPerHost = Constants.lowPriorityMaxConnectionsPerHost
        lowPriorityConfiguration.timeoutIntervalForRequest = Constants.lowPriorityRequestTimeout
        if !protocolClasses.isEmpty {
            lowPriorityConfiguration.protocolClasses = protocolClasses
        }
        let lowPrioritySession = URLSession(
            configuration: lowPriorityConfiguration, delegate: delegate, delegateQueue: nil
        )

        // A dedicated session for file downloads (previews, offline sync). Same cookie jar and trust
        // handling as the main session, but a generous request (inactivity) timeout so a large or slow
        // transfer isn't killed by the interactive 15s budget. This was the cause of "downloads are
        // hyper slow": on the main session, large downloads timed out at 15s and retried in a loop.
        let downloadConfiguration = URLSessionConfiguration.default
        downloadConfiguration.httpCookieStorage = cookieStorage
        downloadConfiguration.httpCookieAcceptPolicy = .always
        downloadConfiguration.httpShouldSetCookies = true
        downloadConfiguration.timeoutIntervalForRequest = Constants.downloadRequestTimeout
        if !protocolClasses.isEmpty {
            downloadConfiguration.protocolClasses = protocolClasses
        }
        let downloadSession = URLSession(
            configuration: downloadConfiguration, delegate: delegate, delegateQueue: nil
        )

        @Sendable func streamToFile(
            _ request: URLRequest, using downloadSession: URLSession
        ) async throws -> (URL, HTTPURLResponse) {
            let temporaryURL: URL
            let response: URLResponse
            do {
                (temporaryURL, response) = try await downloadSession.download(for: request)
            } catch {
                throw NetworkError.from(error)
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NetworkError.invalidResponse
            }
            // `session.download` deletes its temp file the moment this closure returns, so
            // move it somewhere the caller controls before handing the URL back.
            let stableURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(Constants.downloadTempFilePrefix)\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: stableURL)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NetworkError.transport(error.localizedDescription)
            }
            return (stableURL, httpResponse)
        }

        /// Stream to a temp file rather than `session.data(for:)` so response size is bounded
        /// by disk, not resident memory; then size-check before loading it in. This path only
        /// ever carries JSON control responses — file-sized payloads use `download` — so the
        /// extra temp-file round-trip is a sub-millisecond cost on a KB-scale body.
        @Sendable func sendInMemory(
            _ request: URLRequest, using inMemorySession: URLSession
        ) async throws -> (Data, HTTPURLResponse) {
            let temporaryURL: URL
            let response: URLResponse
            do {
                (temporaryURL, response) = try await inMemorySession.download(for: request)
            } catch {
                throw NetworkError.from(error)
            }
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            let byteCount = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard byteCount <= maxInMemoryResponseBytes else {
                throw NetworkError.responseTooLarge
            }
            do {
                return try (Data(contentsOf: temporaryURL), httpResponse)
            } catch {
                throw NetworkError.transport(error.localizedDescription)
            }
        }

        return NetworkClient(
            send: { try await sendInMemory($0, using: session) },
            lowPrioritySend: { try await sendInMemory($0, using: lowPrioritySession) },
            upload: { request, bodyFileURL, onProgress in
                let data: Data
                let response: URLResponse
                do {
                    // A dedicated delegate for progress only. It carries no challenge method,
                    // so connection level challenges (server trust) are handled by
                    // `URLSessionAuthDelegate`'s session level callback.
                    (data, response) = try await session.upload(
                        for: request,
                        fromFile: bodyFileURL,
                        delegate: UploadProgressDelegate(onProgress: onProgress)
                    )
                } catch {
                    throw NetworkError.from(error)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                return (data, httpResponse)
            },
            download: { request in
                try await streamToFile(request, using: downloadSession)
            },
            downloadWithProgress: { request, onProgress in
                let holder = DownloadTaskHolder()
                let observationBox = ProgressObservationBox()
                let throttle = ProgressThrottle(onProgress: onProgress)
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) in
                        // A completion handler task, NOT a download delegate: the delegate's per chunk
                        // `didWriteData` runs on the session's serial delegate queue and applies
                        // backpressure to the socket, which throttled the transfer. Progress instead
                        // comes from the task's own `NSProgress` via KVO, which never touches that
                        // queue. Server trust still falls through to the session `URLSessionAuthDelegate`.
                        let task = downloadSession.downloadTask(with: request) { temporaryURL, response, error in
                            observationBox.invalidate()
                            if let error {
                                continuation.resume(throwing: NetworkError.from(error))
                                return
                            }
                            guard let temporaryURL, let httpResponse = response as? HTTPURLResponse else {
                                continuation.resume(throwing: NetworkError.invalidResponse)
                                return
                            }
                            // The system deletes `temporaryURL` the instant this returns, so move it
                            // synchronously to a stable location the caller owns.
                            let stableURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("\(Constants.downloadTempFilePrefix)\(UUID().uuidString)")
                            do {
                                try FileManager.default.moveItem(at: temporaryURL, to: stableURL)
                                continuation.resume(returning: (stableURL, httpResponse))
                            } catch {
                                continuation.resume(throwing: NetworkError.transport(error.localizedDescription))
                            }
                        }
                        let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                            throttle.report(progress.fractionCompleted)
                        }
                        observationBox.set(observation)
                        if holder.store(task) {
                            task.resume()
                        } else {
                            // Cancelled before the task started: cancel it so its completion handler
                            // resumes the continuation with the cancellation error, not a leak.
                            observationBox.invalidate()
                            task.cancel()
                        }
                    }
                } onCancel: {
                    holder.cancel()
                }
            },
            lowPriorityDownload: { request in
                try await streamToFile(request, using: lowPrioritySession)
            },
            flushDownloadConnections: {
                await withCheckedContinuation { continuation in
                    downloadSession.flush { continuation.resume() }
                }
            }
        )
    }
}

extension NetworkClient: DependencyKey {
    public static var liveValue: NetworkClient {
        @Dependency(\.cookieStorage) var cookieStorage
        return .live(cookieStorage: cookieStorage)
    }
}

public extension DependencyValues {
    var networkClient: NetworkClient {
        get { self[NetworkClient.self] }
        set { self[NetworkClient.self] = newValue }
    }
}
