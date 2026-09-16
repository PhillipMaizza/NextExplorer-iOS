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
                try await streamToFile(request, using: session)
            },
            lowPriorityDownload: { request in
                try await streamToFile(request, using: lowPrioritySession)
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
