import Dependencies
import Foundation

extension NetworkClient {
    /// Ceiling on a response buffered by `send`. The `send` path exists only for JSON control
    /// responses (listings, share lists, editor content) — anything file-sized goes through
    /// `download`, which streams to disk. 32 MB is far above any legitimate JSON payload while
    /// still cutting off a hostile server trying to exhaust memory here.
    public static let defaultMaxInMemoryResponseBytes = 32 * 1024 * 1024

    public static func live(
        trustEvaluator: ServerTrustEvaluating = DefaultServerTrustEvaluator(),
        cookieStorage: HTTPCookieStorage = .shared,
        protocolClasses: [AnyClass] = [],
        maxInMemoryResponseBytes: Int = NetworkClient.defaultMaxInMemoryResponseBytes
    ) -> NetworkClient {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        // A dead or far-away server shouldn't hang a request for the URLSession default of
        // 60s — the launch session check and every tap has to give up sooner than that.
        configuration.timeoutIntervalForRequest = 15
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses
        }

        let delegate = URLSessionAuthDelegate(trustEvaluator: trustEvaluator)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        return NetworkClient(
            send: { request in
                // Stream to a temp file rather than `session.data(for:)` so response size is
                // bounded by disk, not resident memory; then size-check before loading it in.
                // `send` only ever carries JSON control responses — file-sized payloads use
                // `download` — so the extra temp-file round-trip is a sub-millisecond cost on
                // a KB-scale body.
                let temporaryURL: URL
                let response: URLResponse
                do {
                    (temporaryURL, response) = try await session.download(for: request)
                } catch {
                    throw NetworkError.transport(error.localizedDescription)
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
                    return (try Data(contentsOf: temporaryURL), httpResponse)
                } catch {
                    throw NetworkError.transport(error.localizedDescription)
                }
            },
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
                    throw NetworkError.transport(error.localizedDescription)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                return (data, httpResponse)
            },
            download: { request in
                let temporaryURL: URL
                let response: URLResponse
                do {
                    (temporaryURL, response) = try await session.download(for: request)
                } catch {
                    throw NetworkError.transport(error.localizedDescription)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw NetworkError.invalidResponse
                }
                // `session.download` deletes its temp file the moment this closure returns, so
                // move it somewhere the caller controls before handing the URL back.
                let stableURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("download-\(UUID().uuidString)")
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: stableURL)
                } catch {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw NetworkError.transport(error.localizedDescription)
                }
                return (stableURL, httpResponse)
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

extension DependencyValues {
    public var networkClient: NetworkClient {
        get { self[NetworkClient.self] }
        set { self[NetworkClient.self] = newValue }
    }
}
