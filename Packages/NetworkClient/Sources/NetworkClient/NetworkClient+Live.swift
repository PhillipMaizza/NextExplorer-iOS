import Dependencies
import Foundation

private enum Constants {
    static let interactiveRequestTimeout: TimeInterval = 15
    static let lowPriorityRequestTimeout: TimeInterval = 60
    static let lowPriorityMaxConnectionsPerHost = 2
    static let downloadRequestTimeout: TimeInterval = 60
}

public extension NetworkClient {
    static let mutationRequestTimeout: TimeInterval = 300

    static func markingAsMutation(_ request: URLRequest) -> URLRequest {
        var request = request
        request.timeoutInterval = max(request.timeoutInterval, mutationRequestTimeout)
        return request
    }

    /// True for a request that went through `markingAsMutation`.
    static func isMutation(_ request: URLRequest) -> Bool {
        request.timeoutInterval >= mutationRequestTimeout
    }
}

public extension NetworkClient {
    static let defaultMaxInMemoryResponseBytes = 32 * 1024 * 1024

    static let downloadTemporaryFilePrefix = "download-"

    /// The first few kilobytes of a downloaded body, enough to recognize a proxy's error page.
    internal static func prefix(of fileURL: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4096)) ?? Data()
    }

    static func live(
        trustEvaluator: ServerTrustEvaluating = DefaultServerTrustEvaluator(),
        certificates: ClientCertificateChallengeHandler = .shared,
        cookieStorage: HTTPCookieStorage = .appSession,
        protocolClasses: [AnyClass] = [],
        maxInMemoryResponseBytes: Int = NetworkClient.defaultMaxInMemoryResponseBytes
    ) -> NetworkClient {
        /// Every session shares the cookie jar and trust handling and differs only in its budgets.
        func makeConfiguration(
            requestTimeout: TimeInterval,
            maxConnectionsPerHost: Int? = nil
        ) -> URLSessionConfiguration {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = nil
            configuration.httpCookieStorage = cookieStorage
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.timeoutIntervalForRequest = requestTimeout
            if let maxConnectionsPerHost {
                configuration.httpMaximumConnectionsPerHost = maxConnectionsPerHost
            }
            if !protocolClasses.isEmpty {
                configuration.protocolClasses = protocolClasses
            }
            return configuration
        }

        let delegate = URLSessionAuthDelegate(trustEvaluator: trustEvaluator, certificates: certificates)
        let session = ReplaceableSession(
            configuration: makeConfiguration(requestTimeout: Constants.interactiveRequestTimeout),
            delegate: delegate
        )

        let lowPrioritySession = ReplaceableSession(
            configuration: makeConfiguration(
                requestTimeout: Constants.lowPriorityRequestTimeout,
                maxConnectionsPerHost: Constants.lowPriorityMaxConnectionsPerHost
            ),
            delegate: delegate
        )

        let downloadSession = ReplaceableSession(
            configuration: makeConfiguration(requestTimeout: Constants.downloadRequestTimeout),
            delegate: delegate
        )

        certificates.replaceOnCertificateChange([session, lowPrioritySession, downloadSession])

        // Checks a finished download's response and moves its body somewhere the caller owns: the
        // system deletes `temporaryURL` once the download call or completion handler returns.
        @Sendable func finishDownload(
            _ request: URLRequest, temporaryURL: URL, response: URLResponse?
        ) throws -> (URL, HTTPURLResponse) {
            guard let httpResponse = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NetworkError.invalidResponse
            }
            if let error = certificates.certificateError(
                status: httpResponse.statusCode, bodyPrefix: NetworkClient.prefix(of: temporaryURL), url: request.url
            ) {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
            certificates.recordResponse(for: request.url)
            let stableURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(NetworkClient.downloadTemporaryFilePrefix)\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: stableURL)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NetworkError.transport(error.localizedDescription)
            }
            return (stableURL, httpResponse)
        }

        @Sendable func streamToFile(
            _ request: URLRequest, using downloadSession: ReplaceableSession
        ) async throws -> (URL, HTTPURLResponse) {
            let temporaryURL: URL
            let response: URLResponse
            do {
                (temporaryURL, response) = try await downloadSession.current.download(for: request)
            } catch {
                throw NetworkError.from(error, url: request.url, certificates: certificates)
            }
            return try finishDownload(request, temporaryURL: temporaryURL, response: response)
        }

        @Sendable func sendInMemory(
            _ originalRequest: URLRequest, using inMemorySession: ReplaceableSession
        ) async throws -> (Data, HTTPURLResponse) {
            let request = originalRequest
            let temporaryURL: URL
            let response: URLResponse
            do {
                (temporaryURL, response) = try await inMemorySession.current.download(for: request)
            } catch {
                throw NetworkError.from(
                    error,
                    url: request.url,
                    isMutation: NetworkClient.isMutation(request),
                    certificates: certificates
                )
            }
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            if let error = certificates.certificateError(
                status: httpResponse.statusCode, bodyPrefix: NetworkClient.prefix(of: temporaryURL), url: request.url
            ) {
                throw error
            }
            certificates.recordResponse(for: request.url)
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

        // Line by line as the server writes them, for a progress stream; the body stays capped like `send`'s.
        @Sendable func sendLines(
            _ request: URLRequest, onLine: @escaping @Sendable (Data) -> Void
        ) async throws -> (Data, HTTPURLResponse) {
            let holder = DownloadTaskHolder()
            let body: Data
            let response: URLResponse?
            do {
                (body, response) = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        let task = session.current.dataTask(with: request)
                        task.delegate = LineStreamDelegate(maxBytes: maxInMemoryResponseBytes, onLine: onLine) {
                            continuation.resume(with: $0)
                        }
                        if holder.store(task) {
                            task.resume()
                        } else {
                            // Cancelled before it started: cancelling ends it through the delegate, no leak.
                            task.cancel()
                        }
                    }
                } onCancel: {
                    holder.cancel()
                }
            } catch let error as NetworkError {
                throw error
            } catch {
                throw NetworkError.from(
                    error,
                    url: request.url,
                    isMutation: NetworkClient.isMutation(request),
                    certificates: certificates
                )
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            if let error = certificates.certificateError(
                status: httpResponse.statusCode, bodyPrefix: body, url: request.url
            ) {
                throw error
            }
            certificates.recordResponse(for: request.url)
            return (body, httpResponse)
        }

        return NetworkClient(
            send: { try await sendInMemory($0, using: session) },
            lowPrioritySend: { try await sendInMemory($0, using: lowPrioritySession) },
            sendStreamingLines: { request, onLine in try await sendLines(request, onLine: onLine) },
            upload: { originalRequest, bodyFileURL, onProgress in
                let request = NetworkClient.markingAsMutation(originalRequest)
                let data: Data
                let response: URLResponse
                do {
                    // A dedicated delegate for progress only. It carries no challenge method,
                    // so connection level challenges (server trust) are handled by
                    // `URLSessionAuthDelegate`'s session level callback.
                    (data, response) = try await session.current.upload(
                        for: request,
                        fromFile: bodyFileURL,
                        delegate: UploadProgressDelegate(onProgress: onProgress)
                    )
                } catch {
                    throw NetworkError.from(error, url: request.url, isMutation: true, certificates: certificates)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                if let error = certificates.certificateError(
                    status: httpResponse.statusCode,
                    bodyPrefix: data,
                    url: request.url
                ) {
                    throw error
                }
                certificates.recordResponse(for: request.url)
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
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                        (URL, HTTPURLResponse),
                        Error
                    >) in
                        let task = downloadSession.current
                            .downloadTask(with: request) { temporaryURL, response, error in
                                observationBox.invalidate()
                                if let error {
                                    continuation.resume(throwing: NetworkError.from(
                                        error,
                                        url: request.url,
                                        certificates: certificates
                                    ))
                                    return
                                }
                                guard let temporaryURL else {
                                    continuation.resume(throwing: NetworkError.invalidResponse)
                                    return
                                }
                                continuation.resume(with: Result {
                                    try finishDownload(request, temporaryURL: temporaryURL, response: response)
                                })
                            }
                        let observation = task.observe(\.countOfBytesReceived, options: [.new]) { task, _ in
                            let expected = task.countOfBytesExpectedToReceive
                            throttle.report(TransferProgress(
                                receivedBytes: task.countOfBytesReceived,
                                expectedBytes: expected > 0 ? expected : nil
                            ))
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
                    downloadSession.current.flush { continuation.resume() }
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
